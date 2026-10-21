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
import 'package:david/src/data/case_packs.dart';
import 'package:david/src/domain/models.dart';
import 'package:david/src/retrieval/text_match.dart';

const exportPath = 'service/david_lab/cases.json';

/// Edge cases for the matcher that the fixtures do not happen to contain.
const _edgePairs = <(String, String)>[
  ('Night crew found no sign of a door ajar at any point.', 'door ajar'),
  ('No alarm sounded. Door ajar for eleven minutes.', 'door ajar'),
  (
    'Telematics shows no integration defect and miles are down.',
    'integration defect',
  ),
  ('The unrelated party paid on time.', 'related party'),
  ('Acetylene 42.5 ppm. Not a cooling issue.', 'acetylene 42 5 ppm'),
  ('Never once was the door ajar.', 'door ajar'),
  ('The door was ajar; no compressor fault.', 'door was ajar'),
  ('The door was ajar; no compressor fault.', 'compressor fault'),
  ("It wasn't without a related party.", 'related party'),
];

Map<String, Object?> exportCases() {
  final cases = [
    for (final caseFile in CasePacks.all)
      {
        'id': caseFile.id,
        'title': caseFile.title,
        'kind': caseFile.kind == CaseKind.dueDiligence
            ? 'due_diligence'
            : 'physical',
        'question': caseFile.question,
        'loop': switch (LoopRouter.decide(caseFile).kind) {
          AgentLoopKind.planExecute => 'plan-execute',
          AgentLoopKind.react => 'react',
          AgentLoopKind.panelVote => 'panel-vote',
        },
        'evidence': [
          for (final unit in caseFile.evidence)
            {
              'id': unit.id,
              'text': unit.searchableText,
              'quarantined': containsInstructionOverride(unit.searchableText),
            },
        ],
        'hypotheses': [
          for (final hypothesis in caseFile.hypotheses)
            {
              'id': hypothesis.id,
              'title': hypothesis.title,
              'support': [
                for (final s in hypothesis.support) [s.phrase, s.weight],
              ],
              'contradict': [
                for (final s in hypothesis.contradict) [s.phrase, s.weight],
              ],
            },
        ],
      },
  ];
  final golden = <List<Object>>[
    for (final caseFile in CasePacks.all)
      for (final unit in caseFile.evidence)
        for (final phrase in {
          for (final hypothesis in caseFile.hypotheses) ...[
            for (final s in hypothesis.support) s.phrase,
            for (final s in hypothesis.contradict) s.phrase,
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
