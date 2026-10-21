import '../data/builders.dart';
import '../domain/models.dart';
import '../jobs/engagement_service.dart';
import 'models.dart';

/// Turns a stored engagement into the agent's input. The company's deal-breakers
/// become extra risk questions, with the same ids the service uses, so the
/// model's weights line up with the risks the desk scores.
Engagement buildEngagement(UserEngagement engagement, CompanyProfile profile) {
  final spec = engagement.spec?.spec;
  if (spec == null) {
    throw StateError('The engagement has no pinned spec to build from.');
  }
  final units = [
    for (final item in engagement.evidence)
      record(
        id: item.id,
        caseId: engagement.id,
        title: item.title,
        text: item.text,
        observedAt:
            DateTime.tryParse(item.observedAt)?.toUtc() ?? engagement.createdAt,
        site: engagement.counterparty,
        modality: item.kind == 'metric' ? 'metrics' : 'records',
        source: item.source.isEmpty ? 'Owner' : item.source,
        collector: 'Owner',
      ),
  ];
  final risks = [
    for (final risk in spec.risks)
      RiskQuestion(
        id: risk.id,
        title: risk.title,
        statement: risk.statement,
        actionIfLead: risk.action.isEmpty
            ? 'Hold until this risk is resolved.'
            : risk.action,
        outcome: risk.outcome.decision,
        dealBreaker: risk.dealBreaker,
      ),
    for (var i = 0; i < profile.dealBreakers.length; i++)
      RiskQuestion(
        id: 'profile-breaker-${i + 1}',
        title: 'Your deal-breaker',
        statement: profile.dealBreakers[i],
        actionIfLead: 'Walk away.',
        outcome: Decision.walkAway,
        dealBreaker: true,
      ),
  ];
  final modalities = <String>{
    for (final check in spec.checks)
      check.evidenceKind == SpecEvidenceKind.metric ? 'metrics' : 'records',
  };
  return Engagement(
    id: engagement.id,
    dealType: spec.dealType,
    title: spec.name,
    subject: engagement.counterparty,
    question: spec.question,
    summary: engagement.context.isEmpty ? spec.question : engagement.context,
    site: engagement.jurisdiction.isEmpty
        ? engagement.counterparty
        : engagement.jurisdiction,
    openedAt: engagement.createdAt,
    decisionCriteria: spec.decisionCriteria,
    expectedModalities: modalities.toList(),
    plan: [
      for (final check in spec.checks)
        PlannedQuery(
          purpose: check.title,
          text: check.query,
          modality: check.evidenceKind == SpecEvidenceKind.metric
              ? 'metrics'
              : 'records',
        ),
    ],
    exampleQueries: [for (final check in spec.checks) check.query],
    evidence: units,
    riskQuestions: risks,
  );
}

/// A "proceed" is downgraded when the deal is larger than the most the company
/// will expose to one counterparty. The memo then names the limit as a condition.
InvestigationReport applyExposureRule(
  InvestigationReport report, {
  required double dealValue,
  required double maxExposure,
  required String currency,
}) {
  if (maxExposure <= 0 ||
      dealValue <= maxExposure ||
      report.decision != Decision.proceed) {
    return report;
  }
  return InvestigationReport(
    headline: report.headline,
    resolved: report.resolved,
    leadRiskId: report.leadRiskId,
    confidence: report.confidence,
    decisionNote: report.decisionNote,
    recommendedAction: report.recommendedAction,
    findings: report.findings,
    competitors: report.competitors,
    gaps: report.gaps,
    nextCollections: report.nextCollections,
    citedEvidenceIds: report.citedEvidenceIds,
    decision: Decision.proceedWithConditions,
    triggeredDealBreakers: report.triggeredDealBreakers,
    conditions: [
      ...report.conditions,
      'Reduce the exposure to $currency ${maxExposure.toStringAsFixed(0)} or less, the company maximum for one counterparty.',
    ],
  );
}

/// The same run, with its memo replaced.
AgentRun withReport(AgentRun run, InvestigationReport report) {
  return AgentRun(
    caseId: run.caseId,
    policyId: run.policyId,
    steps: run.steps,
    retrieved: run.retrieved,
    judgments: run.judgments,
    report: report,
    control: run.control,
    providerId: run.providerId,
    modelId: run.modelId,
    inputTokens: run.inputTokens,
    outputTokens: run.outputTokens,
  );
}
