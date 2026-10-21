import 'package:david/src/agent/provider.dart';
import 'package:david/src/data/engagement_packs.dart';
import 'package:david/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agent = DemoProvider();

  test('the demo provider is offline and records the policy id', () {
    expect(agent.offline, isTrue);
    expect(agent.id, DemoProvider.idValue);
    final run = agent.run(EngagementPacks.byId('brightline-supply'));
    expect(run.policyId, AgentRun.policyIdValue);
  });

  test(
    'brightline lead is delivery risk, and a negated lien is not distress',
    () {
      final brightline = EngagementPacks.byId('brightline-supply');
      final run = agent.run(brightline);

      expect(run.report.resolved, isTrue);
      expect(run.report.leadRiskId, 'delivery-reliability');
      expect(run.report.recommendedAction, contains('milestones'));

      final distress = _judgment(run, 'financial-distress');
      // "no tax lien" must not count as a tax lien.
      expect(distress.matchedSupport, isEmpty);
      expect(distress.matchedContradict, contains('good standing'));
      expect(distress.net, lessThan(0));

      final shell = _judgment(run, 'shell-or-fraud');
      expect(shell.matchedSupport, isEmpty);
      expect(shell.matchedContradict, contains('formed in 2016'));

      _expectGrounded(brightline, run);
      expect(run.steps.map((step) => step.stage), contains(AgentStage.scope));
      expect(run.steps.where((step) => step.riskProbe), isNotEmpty);
    },
  );

  test('corvid lead is the successor entity, not a healthy customer', () {
    final corvid = EngagementPacks.byId('corvid-retail');
    final run = agent.run(corvid);

    expect(run.report.resolved, isTrue);
    expect(run.report.leadRiskId, 'successor-entity');
    expect(run.report.recommendedAction, contains('Corvid Retail Holdings'));
    expect(run.judgments[1].riskId, 'slow-payer');
    expect(_judgment(run, 'healthy-customer').net, lessThan(0));
    _expectGrounded(corvid, run);
  });

  test('northline prefers the related party and ignores negated telematics defects', () {
    final northline = EngagementPacks.byId('northline-logistics');
    final run = agent.run(northline);

    expect(run.report.resolved, isTrue);
    expect(run.report.leadRiskId, 'related-party-round-trip');
    expect(run.judgments[1].riskId, 'channel-stuffing');
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
}

RiskJudgment _judgment(AgentRun run, String id) {
  return run.judgments.firstWhere((judgment) => judgment.riskId == id);
}

void _expectGrounded(Engagement engagement, AgentRun run) {
  final ids = engagement.evidence.map((unit) => unit.id).toSet();
  expect(ids, hasLength(engagement.evidence.length));
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
