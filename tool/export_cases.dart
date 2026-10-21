/// Writes the desk case packs to `service/david_lab/cases.json`.
///
/// The job service scores the same fixtures the desk does, so the desk is the
/// only place a case is written. Each row of `phrase_golden` is the desk's
/// own phrase-match verdict, and the service tests must agree with every row.
///
/// Run from the repo root after editing `lib/src/data/`:
///
///     dart run tool/export_cases.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:david/src/control/rails.dart';
import 'package:david/src/control/router.dart';
import 'package:david/src/data/engagement_packs.dart';
import 'package:david/src/domain/models.dart';
import 'package:david/src/retrieval/text_match.dart';

const exportPath = 'service/david_lab/cases.json';

/// Edge cases for the matcher that the fixtures do not happen to contain.
const _edgePairs = <(String, String)>[
  (
    'Our visit found no sign of a mail drop address at any point.',
    'mail drop address',
  ),
  (
    'No dispute. Mail drop address on every invoice footer.',
    'mail drop address',
  ),
  (
    'Telematics shows no integration defect and miles are down.',
    'integration defect',
  ),
  ('The unrelated party paid on time.', 'related party'),
  (
    'Revenue rose 38.5 percent. Not a seasonal peak.',
    'revenue rose 38 5 percent',
  ),
  ('Never once was the deposit late.', 'deposit late'),
  ('The invoice was paid; no tax lien on file.', 'invoice was paid'),
  ('The invoice was paid; no tax lien on file.', 'tax lien'),
  ("It wasn't without a related party.", 'related party'),
];

Map<String, Object?> exportCases() {
  final cases = [
    for (final engagement in EngagementPacks.all)
      {
        'id': engagement.id,
        'title': engagement.title,
        'deal_type': engagement.dealType.name,
        'question': engagement.question,
        'loop': switch (LoopRouter.decide(engagement).kind) {
          AgentLoopKind.planExecute => 'plan-execute',
          AgentLoopKind.react => 'react',
          AgentLoopKind.panelVote => 'panel-vote',
        },
        'evidence': [
          for (final unit in engagement.evidence)
            {
              'id': unit.id,
              'text': unit.searchableText,
              'quarantined': containsInstructionOverride(unit.searchableText),
            },
        ],
        'risk_questions': [
          for (final risk in engagement.riskQuestions)
            {
              'id': risk.id,
              'title': risk.title,
              'statement': risk.statement,
              'support': [
                for (final s in risk.support) [s.phrase, s.weight],
              ],
              'contradict': [
                for (final s in risk.contradict) [s.phrase, s.weight],
              ],
            },
        ],
      },
  ];
  final golden = <List<Object>>[
    for (final engagement in EngagementPacks.all)
      for (final unit in engagement.evidence)
        for (final phrase in {
          for (final risk in engagement.riskQuestions) ...[
            for (final s in risk.support) s.phrase,
            for (final s in risk.contradict) s.phrase,
          ],
        })
          if (_candidate(unit.searchableText, phrase))
            [
              unit.searchableText,
              phrase,
              phraseMatches(unit.searchableText, phrase),
            ],
    for (final (text, phrase) in _edgePairs)
      [text, phrase, phraseMatches(text, phrase)],
  ];
  return {
    'generated_by': 'tool/export_cases.dart',
    'note':
        'Synthetic fixtures exported from lib/src/data/. Do not edit by hand.',
    'negation_window': negationWindow,
    'cases': cases,
    'phrase_golden': golden,
  };
}

/// Every token of [phrase] appears somewhere in [text]. Other pairs are a
/// trivial no-match and are left out to keep the file small.
bool _candidate(String text, String phrase) {
  final have = phraseTokens(text).toSet();
  return phraseTokens(phrase).every(have.contains);
}

String encodeExport() {
  return '${const JsonEncoder.withIndent('  ').convert(exportCases())}\n';
}

void main() {
  File(exportPath).writeAsStringSync(encodeExport());
  stdout.writeln('Wrote $exportPath');
}
