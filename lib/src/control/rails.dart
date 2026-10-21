import '../domain/models.dart';

/// Instruction-override patterns checked on questions and on retrieved text.
///
/// OWASP LLM01:2025. A match on a question blocks the run. A match inside
/// evidence quarantines that unit so it cannot support a risk.
///
/// Patterns run on [normalizeForScreen] output, so case, zero-width
/// characters, and punctuation between words do not slip past them. This is
/// a tripwire, not a classifier. A paraphrase can still get through.
final instructionOverrides = <RegExp>[
  RegExp(
    r'\bignore (?:all |any |the |your |of |these |those )*(?:previous|prior|above|earlier|preceding)\b',
  ),
  RegExp(
    r'\b(?:disregard|forget|override|bypass) (?:all |any |the |your |these |those |previous |prior |above |earlier )*(?:instructions|rules|policy|guardrails|prompt)\b',
  ),
  RegExp(r'\bnew instructions\b'),
  RegExp(r'\byou are now\b'),
  RegExp(
    r'\bact as (?:an? |the )?(?:admin|administrator|developer|system|root)\b',
  ),
  RegExp(r'\bsystem prompt\b'),
  RegExp(r'\bexfiltrate\b'),
  RegExp(r'\breveal (?:the |your )?(?:api key|secret|password|token)s?\b'),
];

final _invisible = RegExp('[\u00AD\u200B-\u200F\u2060\uFEFF]');
final _nonWord = RegExp(r'[^a-z0-9]+');

/// Lowercase, drop invisible characters, and collapse everything that is not
/// a letter or digit to one space.
String normalizeForScreen(String text) {
  final visible = text.toLowerCase().replaceAll(_invisible, '');
  return ' ${visible.replaceAll(_nonWord, ' ').trim()} ';
}

final _email = RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}');
final _secret = RegExp(r'\b(?:sk|api)[_-][A-Za-z0-9]{8,}\b');

bool containsInstructionOverride(String text) {
  final normalized = normalizeForScreen(text);
  return instructionOverrides.any((pattern) => pattern.hasMatch(normalized));
}

/// True when [text] speaks as if an operational or commercial action already
/// ran. Nothing on the allowlist can do that, so the memo would be lying.
bool claimsExecutedAction(String text) {
  return _executedAction.hasMatch(normalizeForScreen(text));
}

/// Audit and model-context view of a string.
///
/// OWASP LLM02:2025 and the RAG logging cheat sheet: do not put raw
/// identifiers into the tool log. The sealed record is unchanged.
String redactForLog(String text) {
  final clipped = text.length <= 180 ? text : text.substring(0, 180);
  return clipped
      .replaceAll(_email, '[redacted:email]')
      .replaceAll(_secret, '[redacted:secret]');
}

/// Units that name people or carry contact details stay in the engagement
/// store and are never echoed into the audit log.
bool isRestricted(EvidenceUnit unit) {
  return unit.modality == 'counterparty' ||
      unit.modality == 'ownership' ||
      _email.hasMatch(unit.text);
}

class InputScreen {
  const InputScreen({required this.allowed, required this.check});

  final bool allowed;
  final GuardrailCheck check;

  static InputScreen screen({required String question, required bool granted}) {
    if (!granted) {
      return const InputScreen(
        allowed: false,
        check: GuardrailCheck(
          rail: 'input',
          name: 'Case grant',
          verdict: RailVerdict.block,
          detail: 'This principal has no grant for the case.',
        ),
      );
    }
    if (containsInstructionOverride(question)) {
      return const InputScreen(
        allowed: false,
        check: GuardrailCheck(
          rail: 'input',
          name: 'Instruction override',
          verdict: RailVerdict.block,
          detail: 'The question tries to override the investigation policy. The run stops before any search.',
        ),
      );
    }
    if (question.trim().length < 12) {
      return const InputScreen(
        allowed: false,
        check: GuardrailCheck(
          rail: 'input',
          name: 'Question length',
          verdict: RailVerdict.block,
          detail: 'The question is too short to scope an investigation.',
        ),
      );
    }
    return const InputScreen(
      allowed: true,
      check: GuardrailCheck(
        rail: 'input',
        name: 'Instruction override',
        verdict: RailVerdict.pass,
        detail: 'Question accepted as data. It does not rewrite the policy.',
      ),
    );
  }
}

class OutputScreen {
  const OutputScreen({
    required this.allowed,
    required this.check,
    required this.report,
  });

  final bool allowed;
  final GuardrailCheck check;
  final InvestigationReport report;

  static OutputScreen screen({
    required InvestigationReport report,
    required Set<String> retrievedIds,
  }) {
    final missing = report.citedEvidenceIds
        .where((id) => !retrievedIds.contains(id))
        .toList();
    final claimsAction = [
      report.headline,
      report.decisionNote,
      report.recommendedAction,
      ...report.findings,
    ].any(claimsExecutedAction);
    if (missing.isNotEmpty || claimsAction || report.confidence > 0.95) {
      return OutputScreen(
        allowed: false,
        check: GuardrailCheck(
          rail: 'output',
          name: 'Grounded memo',
          verdict: RailVerdict.block,
          detail: missing.isNotEmpty
              ? 'Citation ${missing.first} was not retrieved in this run.'
              : claimsAction
              ? 'The memo spoke as if an action ran that the allowlist cannot perform.'
              : 'Confidence ${(report.confidence * 100).round()}% is above the 95% cap.',
        ),
        report: InvestigationReport(
          headline: 'Output rail held the memo',
          resolved: false,
          leadRiskId: null,
          confidence: 0,
          decisionNote: 'The draft memo failed the output rail. No recommendation is released.',
          recommendedAction:
              'Hold the decision and rerun after the rail failure is fixed.',
          findings: const [],
          competitors: report.competitors,
          gaps: [
            if (missing.isNotEmpty)
              'Ungrounded citation: ${missing.join(', ')}.',
            if (claimsAction)
              'The draft spoke as if an operational tool had already run.',
            if (report.confidence > 0.95)
              'Draft confidence ${(report.confidence * 100).round()}% exceeded the 95% cap.',
          ],
          nextCollections: report.nextCollections,
          citedEvidenceIds: const [],
        ),
      );
    }
    return OutputScreen(
      allowed: true,
      check: const GuardrailCheck(
        rail: 'output',
        name: 'Grounded memo',
        verdict: RailVerdict.pass,
        detail: 'Every citation was retrieved in this run. Confidence stays at or below 95%.',
      ),
      report: report,
    );
  }
}

final _executedAction = RegExp(
  r'\b(?:(?:has|have|was|were) been (?:paid|wired|transferred|released|signed|executed|sent)'
  r'|(?:payment|wire|funds?|deposit|invoice|prepayment) (?:(?:was|were|has been|have been) )?(?:sent|wired|transferred|released|paid)'
  r'|(?:contract|agreement|loi|nda) (?:(?:was|has been) )?(?:signed|executed|countersigned)'
  r'|(?:purchase )?order (?:(?:was|has been) )?(?:placed|executed|filled)'
  r'|(?:email|message|offer) (?:(?:was|has been) )?sent to the (?:counterparty|seller|buyer|vendor|customer))\b',
);
