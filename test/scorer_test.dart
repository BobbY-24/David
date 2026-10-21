import 'package:david/src/agent/scorer.dart';
import 'package:david/src/data/builders.dart';
import 'package:david/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

RetrievalHit hit(String id) {
  return RetrievalHit(
    unit: record(
      id: id,
      caseId: 'case',
      title: 'Title $id',
      text: 'Text of $id.',
      observedAt: utc(2026, 1, 1, 0),
      site: 'site',
      modality: 'records',
      source: 'source',
      collector: 'fixture',
    ),
    score: 1,
    matchedTerms: const [],
  );
}

const risk = RiskQuestion(
  id: 'risk',
  title: 'A risk',
  statement: 'The risk is real.',
  actionIfLead: 'Act.',
  support: [],
  contradict: [],
);

ModelEvidenceWeight w(String id, double weight, [String note = 'why']) {
  return ModelEvidenceWeight(evidenceId: id, weight: weight, note: note);
}

RiskJudgment judge(
  ModelRiskScore score, {
  List<String> retrieved = const ['a', 'b', 'c'],
  Set<String> skip = const {},
  double scale = 1,
}) {
  return ModelScorer([score])
      .judge(risk, [for (final id in retrieved) hit(id)], skip, scale);
}

void main() {
  test('only retrieved, unskipped evidence counts', () {
    final judgment = judge(
      ModelRiskScore(
        riskId: 'risk',
        support: [w('a', 2), w('forged', 3), w('b', 1)],
      ),
      skip: {'b'},
    );
    expect(judgment.supporting.map((h) => h.unit.id), ['a']);
    expect(judgment.supportScore, 2);
  });

  test('weights are clamped and a repeated unit keeps its heaviest weight', () {
    final judgment = judge(
      ModelRiskScore(
        riskId: 'risk',
        support: [w('a', 99), w('b', -4), w('a', 0.5), w('c', double.nan)],
      ),
    );
    expect(judgment.supporting.map((h) => h.unit.id), ['a', 'b']);
    // 3.0 for a, then 0.1 for b at 80%.
    expect(judgment.supportScore, closeTo(3.0 + 0.1 * 0.8, 1e-9));
  });

  test('later entries count for less and a total is capped', () {
    final two = judge(
      ModelRiskScore(riskId: 'risk', support: [w('a', 3), w('b', 3)]),
    );
    expect(two.supportScore, closeTo(3 + 3 * 0.8, 1e-9));

    final many = [for (var i = 0; i < 20; i++) 'u$i'];
    final stuffed = judge(
      ModelRiskScore(
        riskId: 'risk',
        support: [for (final id in many) w(id, 3)],
      ),
      retrieved: many,
    );
    expect(stuffed.supportScore, 8.0);
  });

  test('one decisive unit beats a pile of weak ones', () {
    final weak = [for (var i = 0; i < 10; i++) 'w$i'];
    final scorer = ModelScorer([
      ModelRiskScore(riskId: 'risk', support: [w('big', 3)]),
    ]);
    final decisive = scorer.judge(risk, [hit('big')], const {}, 1);
    final pile = ModelScorer([
      ModelRiskScore(
        riskId: 'risk',
        support: [for (final id in weak) w(id, 0.3)],
      ),
    ]).judge(risk, [for (final id in weak) hit(id)], const {}, 1);
    expect(decisive.supportScore, greaterThan(pile.supportScore));
  });

  test('falsifiers subtract, and a lens can scale them', () {
    final score = ModelRiskScore(
      riskId: 'risk',
      support: [w('a', 2)],
      contradict: [w('b', 1)],
    );
    expect(judge(score).net, closeTo(1, 1e-9));
    expect(judge(score, scale: 2).net, closeTo(0, 1e-9));
    expect(judge(score, scale: 2).contradictScore, closeTo(2, 1e-9));
  });

  test('skipping the strongest unit is the leave-one-out lens', () {
    final score = ModelRiskScore(
      riskId: 'risk',
      support: [w('a', 3), w('b', 1)],
    );
    final full = judge(score);
    final without = judge(score, skip: {'a'});
    expect(without.net, lessThan(full.net));
    expect(without.supporting.map((h) => h.unit.id), ['b']);
  });

  test('notes become labels, falling back to the unit title', () {
    final judgment = judge(
      ModelRiskScore(
        riskId: 'risk',
        support: [w('a', 2, ''), w('b', 1, 'x' * 300)],
      ),
    );
    expect(judgment.matchedSupport.first, 'Title a');
    expect(judgment.matchedSupport.last.length, lessThanOrEqualTo(100));
  });

  test('a risk the model did not mention scores zero', () {
    final judgment = ModelScorer(const []).judge(risk, [hit('a')], const {}, 1);
    expect(judgment.net, 0);
    expect(judgment.supporting, isEmpty);
  });
}
