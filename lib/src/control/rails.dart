import '../domain/models.dart';

/// Instruction-override patterns checked on questions and on retrieved text.
///
/// OWASP LLM01:2025. A match on a question blocks the run. A match inside
/// evidence quarantines that unit so it cannot support a hypothesis.
final instructionOverrides = <RegExp>[
  RegExp(r'ignore (all |any )?(previous|prior|above)', caseSensitive: false),
  RegExp(r'disregard (the |all )?(instructions|rules)', caseSensitive: false),
  RegExp(r'you are now', caseSensitive: false),
  RegExp(r'system prompt', caseSensitive: false),
  RegExp(r'\bexfiltrate\b', caseSensitive: false),
  RegExp(r'reveal (the |your )?(api key|secret)', caseSensitive: false),
];

final _badge = RegExp(r'\bB-\d{3,}\b');
final _email = RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}');
final _secret = RegExp(r'\b(?:sk|api)[_-][A-Za-z0-9]{8,}\b');

bool containsInstructionOverride(String text) {
  return instructionOverrides.any((pattern) => pattern.hasMatch(text));
}

/// Audit and model-context view of a string.
///
/// OWASP LLM02:2025 and the RAG logging cheat sheet: do not put raw
/// identifiers into the tool log. The sealed record is unchanged.
String redactForLog(String text) {
  final clipped = text.length <= 180 ? text : text.substring(0, 180);
  return clipped
      .replaceAll(_badge, '[redacted:badge]')
      .replaceAll(_email, '[redacted:email]')
      .replaceAll(_secret, '[redacted:secret]');
}

bool isRestricted(EvidenceUnit unit) {
  return unit.modality == 'access' ||
      unit.modality == 'counterparty' ||
      _badge.hasMatch(unit.text) ||
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
    final claimsAction = _executedAction.hasMatch(report.recommendedAction);
    if (missing.isNotEmpty || claimsAction || report.confidence > 0.95) {
      return OutputScreen(
        allowed: false,
        check: GuardrailCheck(
          rail: 'output',
          name: 'Grounded memo',
          verdict: RailVerdict.block,
          detail: missing.isNotEmpty
              ? 'Citation ${missing.first} was not retrieved in this run.'
              : 'The memo claimed an action the allowlist cannot perform, or a confidence above the cap.',
        ),
        report: InvestigationReport(
          headline: 'Output rail held the memo',
          resolved: false,
          leadHypothesisId: null,
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
  r'\b(re-energized|reenergized|lots released|payment sent|wire sent)\b',
  caseSensitive: false,
);
