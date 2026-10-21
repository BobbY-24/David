import 'package:david/src/agent/engagement_agent.dart';
import 'package:david/src/data/builders.dart';
import 'package:david/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Engagement deal({
  required List<RiskQuestion> risks,
  required Map<String, String> notes,
}) {
  return Engagement(
    id: 'deal',
    dealType: DealType.vendor,
    title: 'Deal',
    subject: 'Fixture',
    question: 'Should we proceed with this supplier?',
    summary: 'Fixture.',
    site: 'books',
    openedAt: utc(2026, 1, 1, 0),
    decisionCriteria: const ['Use sealed evidence.'],
    expectedModalities: const ['records'],
    plan: const [
      PlannedQuery(purpose: 'Read', text: 'supplier verified mail drop'),
    ],
    exampleQueries: const ['supplier'],
    evidence: [
      for (final entry in notes.entries)
        record(
          id: entry.key,
          caseId: 'deal',
          title: 'Note ${entry.key}',
          text: entry.value,
          observedAt: utc(2026, 1, 1, 1),
          site: 'books',
          modality: 'records',
          source: 'file',
          collector: 'fixture',
        ),
    ],
    riskQuestions: risks,
  );
}

RiskQuestion risk(
  String id,
  String phrase, {
  double weight = 2.0,
  Decision outcome = Decision.proceed,
  bool dealBreaker = false,
  String action = 'Act on it.',
}) {
  return RiskQuestion(
    id: id,
    title: 'Risk $id',
    statement: 'Statement for $id.',
    actionIfLead: action,
    support: [Signature(phrase, weight)],
    outcome: outcome,
    dealBreaker: dealBreaker,
  );
}

void main() {
  test('a resolved lead recommends its own outcome', () {
    final run = const EngagementAgent().run(
      deal(
        risks: [
          risk('cleared', 'verified by the bank', outcome: Decision.proceed),
        ],
        notes: {'n1': 'The supplier was verified by the bank.'},
      ),
    );
    expect(run.report.resolved, isTrue);
    expect(run.report.decision, Decision.proceed);
    expect(run.report.triggeredDealBreakers, isEmpty);
  });

  test('a conditional lead carries its action as the condition', () {
    final run = const EngagementAgent().run(
      deal(
        risks: [
          risk(
            'capped',
            'verified by the bank',
            outcome: Decision.proceedWithConditions,
            action: 'Pay in milestones.',
          ),
        ],
        notes: {'n1': 'The supplier was verified by the bank.'},
      ),
    );
    expect(run.report.decision, Decision.proceedWithConditions);
    expect(run.report.conditions, ['Pay in milestones.']);
  });

  test(
    'a triggered deal-breaker forces walk-away even when another risk leads',
    () {
      final run = const EngagementAgent().run(
        deal(
          risks: [
            risk('cleared', 'verified by the bank', weight: 3.0),
            risk(
              'fraud',
              'mail drop address',
              weight: 1.5,
              outcome: Decision.proceed,
              dealBreaker: true,
            ),
          ],
          notes: {
            'n1': 'The supplier was verified by the bank.',
            'n2': 'Invoices go to a mail drop address.',
          },
        ),
      );
      expect(run.report.leadRiskId, 'cleared');
      expect(run.report.resolved, isTrue);
      expect(run.report.triggeredDealBreakers, ['fraud']);
      expect(run.report.decision, Decision.walkAway);
    },
  );

  test('a weak deal-breaker with little support does not trigger', () {
    final run = const EngagementAgent().run(
      deal(
        risks: [
          risk(
            'cleared',
            'verified by the bank',
            weight: 3.0,
            outcome: Decision.proceed,
          ),
          risk('fraud', 'mail drop address', weight: 0.3, dealBreaker: true),
        ],
        notes: {
          'n1': 'The supplier was verified by the bank.',
          'n2': 'Invoices go to a mail drop address.',
        },
      ),
    );
    expect(run.report.triggeredDealBreakers, isEmpty);
    expect(run.report.decision, Decision.proceed);
  });

  test('an unresolved memo holds', () {
    final run = const EngagementAgent().run(
      deal(
        risks: [
          risk('one', 'verified by the bank', outcome: Decision.proceed),
          risk('two', 'verified by the bank', outcome: Decision.walkAway),
        ],
        notes: {'n1': 'The supplier was verified by the bank.'},
      ),
    );
    expect(run.report.resolved, isFalse);
    expect(run.report.decision, Decision.hold);
  });

  test(
    'a user risk with no phrases is probed with its title and statement',
    () {
      final run = const EngagementAgent().run(
        deal(
          risks: [
            const RiskQuestion(
              id: 'custom',
              title: 'Late payment history',
              statement: 'The customer pays late.',
              actionIfLead: 'Ask for a deposit.',
            ),
          ],
          notes: {'n1': 'Late payment history is recorded for this customer.'},
        ),
      );
      final probe = run.steps.firstWhere((step) => step.riskProbe);
      expect(probe.query, contains('Late payment history'));
    },
  );

  test('the Decision labels are the words the desk shows', () {
    expect(Decision.proceedWithConditions.label, 'Proceed with conditions');
    expect(Decision.walkAway.label, 'Walk away');
  });
}
