/// Domain types for a David due-diligence engagement.
///
/// Evidence units are the retrieval atoms. An engagement carries the brief,
/// the sealed corpus, the planned retrieval passes, and the risk questions the
/// agent is allowed to score.
library;

/// The kind of counterparty decision a one-person company is making.
enum DealType { customer, vendor, partner, contractor, acquisition, lease }

/// A metric is one point of a numeric series (revenue, collections, on-time
/// rate). A record is a document, registry entry, or screening result.
enum SourceKind { metric, record }

enum AgentStage { scope, retrieve, gap, adjudicate, report }

class ProvenanceStep {
  const ProvenanceStep({
    required this.actor,
    required this.action,
    required this.at,
    required this.note,
  });

  final String actor;
  final String action;
  final DateTime at;
  final String note;
}

class EvidenceUnit {
  const EvidenceUnit({
    required this.id,
    required this.caseId,
    required this.sourceKind,
    required this.title,
    required this.text,
    required this.observedAt,
    required this.site,
    required this.modality,
    required this.source,
    required this.provenance,
    this.seriesId,
    this.numericValue,
    this.unit,
    this.metadata = const {},
  });

  final String id;
  final String caseId;
  final SourceKind sourceKind;
  final String title;
  final String text;
  final DateTime observedAt;
  final String site;
  final String modality;
  final String source;
  final String? seriesId;
  final double? numericValue;
  final String? unit;
  final Map<String, String> metadata;
  final List<ProvenanceStep> provenance;

  String get searchableText {
    final extra = metadata.entries.map(
      (entry) => '${entry.key} ${entry.value}',
    );
    return [title, text, source, modality, site, ...extra].join(' ');
  }
}

class Signature {
  const Signature(this.phrase, this.weight);

  /// Consecutive tokens that must appear, and must not sit under a negation.
  final String phrase;
  final double weight;
}

class RiskQuestion {
  const RiskQuestion({
    required this.id,
    required this.title,
    required this.statement,
    required this.actionIfLead,
    required this.support,
    required this.contradict,
  });

  final String id;
  final String title;
  final String statement;
  final String actionIfLead;
  final List<Signature> support;
  final List<Signature> contradict;
}

class PlannedQuery {
  const PlannedQuery({
    required this.purpose,
    required this.text,
    this.modality,
    this.sourceKind,
  });

  final String purpose;
  final String text;
  final String? modality;
  final SourceKind? sourceKind;
}

class Engagement {
  const Engagement({
    required this.id,
    required this.dealType,
    required this.title,
    required this.subject,
    required this.question,
    required this.summary,
    required this.site,
    required this.openedAt,
    required this.decisionCriteria,
    required this.expectedModalities,
    required this.plan,
    required this.exampleQueries,
    required this.evidence,
    required this.riskQuestions,
  });

  final String id;
  final DealType dealType;
  final String title;
  final String subject;
  final String question;
  final String summary;
  final String site;
  final DateTime openedAt;
  final List<String> decisionCriteria;
  final List<String> expectedModalities;
  final List<PlannedQuery> plan;
  final List<String> exampleQueries;
  final List<EvidenceUnit> evidence;
  final List<RiskQuestion> riskQuestions;
}

class RetrievalQuery {
  const RetrievalQuery({
    required this.text,
    this.modality,
    this.sourceKind,
    this.site,
    this.limit = 8,
  });

  final String text;
  final String? modality;
  final SourceKind? sourceKind;
  final String? site;
  final int limit;
}

class RetrievalHit {
  const RetrievalHit({
    required this.unit,
    required this.score,
    required this.matchedTerms,
  });

  final EvidenceUnit unit;
  final double score;
  final List<String> matchedTerms;
}

class AgentStep {
  const AgentStep({
    required this.id,
    required this.stage,
    required this.title,
    required this.detail,
    this.tool,
    this.query,
    this.evidenceIds = const [],
    this.riskProbe = false,
  });

  final String id;
  final AgentStage stage;
  final String title;
  final String detail;
  final String? tool;
  final String? query;
  final List<String> evidenceIds;
  final bool riskProbe;
}

class RiskJudgment {
  const RiskJudgment({
    required this.riskId,
    required this.title,
    required this.statement,
    required this.actionIfLead,
    required this.supportScore,
    required this.contradictScore,
    required this.net,
    required this.supporting,
    required this.contradicting,
    required this.matchedSupport,
    required this.matchedContradict,
    required this.missingSupport,
  });

  final String riskId;
  final String title;
  final String statement;
  final String actionIfLead;
  final double supportScore;
  final double contradictScore;
  final double net;
  final List<RetrievalHit> supporting;
  final List<RetrievalHit> contradicting;
  final List<String> matchedSupport;
  final List<String> matchedContradict;
  final List<String> missingSupport;
}

class InvestigationReport {
  const InvestigationReport({
    required this.headline,
    required this.resolved,
    required this.leadRiskId,
    required this.confidence,
    required this.decisionNote,
    required this.recommendedAction,
    required this.findings,
    required this.competitors,
    required this.gaps,
    required this.nextCollections,
    required this.citedEvidenceIds,
  });

  final String headline;
  final bool resolved;
  final String? leadRiskId;
  final double confidence;
  final String decisionNote;
  final String recommendedAction;
  final List<String> findings;
  final List<String> competitors;
  final List<String> gaps;
  final List<String> nextCollections;
  final List<String> citedEvidenceIds;
}

class AgentRun {
  const AgentRun({
    required this.caseId,
    required this.policyId,
    required this.steps,
    required this.retrieved,
    required this.judgments,
    required this.report,
    required this.control,
    this.providerId = demoProviderId,
    this.modelId,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  static const policyIdValue = 'grounded-control-v4';
  static const demoProviderId = 'demo-provider';

  final String caseId;
  final String policyId;
  final List<AgentStep> steps;
  final List<RetrievalHit> retrieved;
  final List<RiskJudgment> judgments;
  final InvestigationReport report;
  final ControlRecord control;

  /// Which provider scored the risks, and the model when one did.
  final String providerId;
  final String? modelId;
  final int inputTokens;
  final int outputTokens;

  bool get usedModel => modelId != null;

  AgentRun withModel({
    required String providerId,
    required String modelId,
    required int inputTokens,
    required int outputTokens,
    List<AgentStep>? steps,
  }) {
    return AgentRun(
      caseId: caseId,
      policyId: policyId,
      steps: steps ?? this.steps,
      retrieved: retrieved,
      judgments: judgments,
      report: report,
      control: control,
      providerId: providerId,
      modelId: modelId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}

enum AgentLoopKind { planExecute, react, panelVote }

/// A flag ran and changed what the run could use, but did not stop it.
enum RailVerdict { pass, flag, block }

class GuardrailCheck {
  const GuardrailCheck({
    required this.rail,
    required this.name,
    required this.verdict,
    required this.detail,
  });

  final String rail;
  final String name;
  final RailVerdict verdict;
  final String detail;
}

class AuditEvent {
  const AuditEvent({
    required this.seq,
    required this.tool,
    required this.decision,
    required this.caseId,
    required this.redactedQuery,
    required this.prevHash,
    required this.hash,
  });

  final int seq;
  final String tool;
  final String decision;
  final String caseId;
  final String redactedQuery;
  final String prevHash;
  final String hash;
}

class SeatVote {
  const SeatVote({
    required this.seatId,
    required this.seatTitle,
    required this.riskId,
    required this.riskTitle,
    required this.net,
    this.margin = 0,
  });

  final String seatId;
  final String seatTitle;
  final String? riskId;
  final String riskTitle;
  final double net;

  /// Lead net minus runner-up net in this seat. Zero on a tie.
  final double margin;
}

/// What the control plane decided for one run.
///
/// The memo stays a grounded score. This record is the router verdict,
/// the rails, the hash-chained tool audit, and the approval hold.
class ControlRecord {
  const ControlRecord({
    required this.principalId,
    required this.loop,
    required this.reason,
    required this.standard,
    required this.escalated,
    required this.guardrails,
    required this.audit,
    required this.toolCalls,
    required this.toolBudget,
    required this.batched,
    required this.approvalRequired,
    required this.approvalNote,
    required this.votes,
    required this.quarantinedEvidenceIds,
    required this.restrictedEvidenceIds,
  });

  final String principalId;
  final AgentLoopKind loop;
  final String reason;
  final String standard;
  final bool escalated;
  final List<GuardrailCheck> guardrails;
  final List<AuditEvent> audit;
  final int toolCalls;
  final int toolBudget;
  final bool batched;
  final bool approvalRequired;
  final String approvalNote;
  final List<SeatVote> votes;
  final List<String> quarantinedEvidenceIds;
  final List<String> restrictedEvidenceIds;

  String get loopLabel => switch (loop) {
    AgentLoopKind.planExecute => 'Plan and execute',
    AgentLoopKind.react => 'ReAct',
    AgentLoopKind.panelVote => 'Panel vote',
  };
}
