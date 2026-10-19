import 'package:fieldline/src/agent/investigation_agent.dart';
import 'package:fieldline/src/data/case_packs.dart';
import 'package:fieldline/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agent = InvestigationAgent();

  test(
    'harbor lead is the internal fault and every citation was retrieved',
    () {
      final harbor = CasePacks.byId('harbor-substation-4');
      final run = agent.investigate(harbor);

      expect(run.policyId, AgentRun.policyIdValue);
      expect(run.report.resolved, isTrue);
      expect(run.report.leadHypothesisId, 'internal-thermal-fault');
      expect(run.judgments.first.net, greaterThan(0));

      final cooling = _judgment(run, 'cooling-failure');
      expect(cooling.matchedSupport, isEmpty);
      expect(cooling.matchedContradict, contains('pump current steady'));
      expect(cooling.net, lessThan(0));

      final drift = _judgment(run, 'calibration-drift');
      expect(drift.net, lessThan(run.judgments.first.net));

      _expectGrounded(harbor, run);
      expect(run.steps.map((step) => step.stage), contains(AgentStage.scope));
      expect(run.steps.where((step) => step.hypothesisProbe), isNotEmpty);
      expect(run.report.recommendedAction, contains('phase B'));
    },
  );

  test('northline prefers the related party and ignores negated telematics defects', () {
    final northline = CasePacks.byId('northline-logistics');
    final run = agent.investigate(northline);

    expect(run.report.resolved, isTrue);
    expect(run.report.leadHypothesisId, 'related-party-round-trip');
    expect(run.judgments[1].hypothesisId, 'channel-stuffing');
    expect(run.judgments[1].net, greaterThan(0));

    final defect = _judgment(run, 'telematics-defect');
    expect(defect.matchedSupport, isEmpty);
    expect(defect.matchedContradict, contains('warehouse occupancy agrees'));
    expect(defect.net, lessThan(0));

    final seasonal = _judgment(run, 'legitimate-seasonal');
    expect(seasonal.matchedSupport, isEmpty);
    expect(seasonal.net, lessThan(0));
    _expectGrounded(northline, run);
  });

  test('vault lead is the open door, not the compressor or the logger', () {
    final vault = CasePacks.byId('vault-c12');
    final run = agent.investigate(vault);

    expect(run.report.resolved, isTrue);
    expect(run.report.leadHypothesisId, 'door-ajar');
    expect(_judgment(run, 'compressor-fault').net, lessThan(0));
    expect(
      _judgment(run, 'logger-fault').matchedContradict,
      contains('second logger rose'),
    );
    expect(_judgment(run, 'planned-defrost').matchedSupport, isEmpty);
    _expectGrounded(vault, run);
  });
}

HypothesisJudgment _judgment(AgentRun run, String id) {
  return run.judgments.firstWhere((judgment) => judgment.hypothesisId == id);
}

void _expectGrounded(InvestigationCase caseFile, AgentRun run) {
  final ids = caseFile.evidence.map((unit) => unit.id).toSet();
  expect(ids, hasLength(caseFile.evidence.length));
  final retrieved = run.retrieved.map((hit) => hit.unit.id).toSet();
  expect(retrieved.every(ids.contains), isTrue);

  for (final step in run.steps) {
    expect(step.evidenceIds.every(ids.contains), isTrue);
  }
  expect(run.report.citedEvidenceIds, isNotEmpty);
  for (final id in run.report.citedEvidenceIds) {
    expect(ids, contains(id));
    expect(retrieved, contains(id));
  }
  for (final judgment in run.judgments) {
    for (final hit in [...judgment.supporting, ...judgment.contradicting]) {
      expect(retrieved, contains(hit.unit.id));
    }
  }
  expect(run.report.confidence, inInclusiveRange(0, 0.95));
}
