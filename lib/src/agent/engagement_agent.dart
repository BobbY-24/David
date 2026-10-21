import 'dart:math' as math;

import '../control/gateway.dart';
import '../control/rails.dart';
import '../control/router.dart';
import '../domain/models.dart';
import '../retrieval/evidence_index.dart';
import 'scorer.dart';

/// A deal-breaker counts once its net reaches this and it has support.
const _dealBreakerNet = 1.0;

/// The phrases a risk is probed with. A user risk has none, so it is probed
/// with its title and statement instead.
String _probeQuery(RiskQuestion risk) {
  final phrases = [
    ...risk.support.map((signature) => signature.phrase),
    ...risk.contradict.map((signature) => signature.phrase),
  ];
  if (phrases.isNotEmpty) {
    return phrases.join(' ');
  }
  return '${risk.title} ${risk.statement}';
}

class _Execution {
  const _Execution({
    required this.steps,
    required this.retrieved,
    required this.judgments,
    required this.report,
    required this.missing,
    required this.votes,
    required this.batched,
    required this.skip,
  });

  final List<AgentStep> steps;
  final List<RetrievalHit> retrieved;
  final List<RiskJudgment> judgments;
  final InvestigationReport report;
  final List<String> missing;
  final List<SeatVote> votes;
  final bool batched;
  final Set<String> skip;
}

/// How a seat reads the shared retrieved set.
///
/// No lens names a risk. Each one is a different test of the same
/// evidence, so seats can disagree without a per-case thumb on the scale.
enum _Lens {
  /// The unweighted score.
  plain,

  /// Each risk loses its single strongest supporting unit. A lead that
  /// rests on one planted or mis-sealed record does not survive.
  leaveOneOut,

  /// Falsifiers count double.
  falsifierWeighted,
}

class _Seat {
  const _Seat(this.id, this.title, this.lens);

  final String id;
  final String title;
  final _Lens lens;
}

const _seats = <_Seat>[
  _Seat('analyst', 'Analyst', _Lens.plain),
  _Seat('robustness', 'Robustness', _Lens.leaveOneOut),
  _Seat('skeptic', 'Skeptic', _Lens.falsifierWeighted),
];

const _resolveMargin = 0.45;

/// Confidence ceiling for a memo the panel released after a thin ReAct margin.
const _panelReleaseCap = 0.5;

/// Engagement entrypoint.
///
/// The router picks plan-and-execute, ReAct, or a panel vote. Every search
/// goes through [ToolGateway]. Rails run before the first search and after
/// the memo. The scorer still cites only retrieved ids.
class EngagementAgent {
  const EngagementAgent({this.scorer = const PhraseScorer()});

  /// Scores each risk question. Phrase matching unless a provider swaps it.
  final RiskScorer scorer;

  AgentRun run(Engagement engagement, {Principal? principal}) {
    final who = principal ?? Principal.deskOperator(engagement.id);
    final gate = ToolGateway(principal: who);
    final quarantined = [
      for (final unit in engagement.evidence)
        if (containsInstructionOverride(unit.searchableText)) unit.id,
    ];
    final restricted = [
      for (final unit in engagement.evidence)
        if (isRestricted(unit)) unit.id,
    ]..sort();
    final input = InputScreen.screen(
      question: engagement.question,
      granted: who.grants(engagement.id),
    );
    if (!input.allowed) {
      return _blocked(
        engagement: engagement,
        principal: who,
        gate: gate,
        input: input.check,
        quarantined: quarantined,
        restricted: restricted,
      );
    }

    final decision = LoopRouter.decide(engagement);
    final index = EvidenceIndex(engagement.evidence);
    final skip = quarantined.toSet();
    var execution = switch (decision.kind) {
      AgentLoopKind.planExecute => _runPlan(engagement, index, gate, skip),
      AgentLoopKind.react => _runReact(engagement, index, gate, skip),
      AgentLoopKind.panelVote => _runVote(engagement, index, gate, skip),
    };

    var loop = decision.kind;
    var reason = decision.reason;
    var standard = decision.standard;
    var escalated = false;
    if (decision.kind == AgentLoopKind.react &&
        _margin(execution.judgments) < _resolveMargin) {
      escalated = true;
      loop = AgentLoopKind.panelVote;
      reason = 'ReAct left a margin under 0.45, so the same evidence was sent to the panel.';
      standard = 'Escalation. A thin ReAct margin is not a place to invent another search. The panel votes on the evidence already retrieved. Only a unanimous panel with a strict lead in every seat can release the memo, and its confidence is capped at 50%.';
      execution = _applyVote(engagement, execution, escalated: true);
    }

    final output = OutputScreen.screen(
      report: execution.report,
      retrievedIds: execution.retrieved.map((hit) => hit.unit.id).toSet(),
    );
    final rails = <GuardrailCheck>[
      input.check,
      GuardrailCheck(
        rail: 'tool',
        name: 'Allowlist and budget',
        verdict: gate.denied.isEmpty ? RailVerdict.pass : RailVerdict.block,
        detail: gate.denied.isEmpty
            ? 'Search is the only tool. ${gate.used} call${gate.used == 1 ? '' : 's'} of ${gate.budget} used.'
            : 'Denied: ${gate.denied.join(', ')}.',
      ),
      GuardrailCheck(
        rail: 'data',
        name: 'Case scope and redaction',
        verdict: quarantined.isEmpty ? RailVerdict.pass : RailVerdict.flag,
        detail: quarantined.isEmpty
            ? 'No retrieved unit contained an instruction override. ${restricted.length} restricted unit${restricted.length == 1 ? '' : 's'} stay in the case store. The audit log stores redacted queries.'
            : 'Quarantined ${quarantined.length} unit${quarantined.length == 1 ? '' : 's'} that tried to instruct the policy.',
      ),
      output.check,
      const GuardrailCheck(
        rail: 'action',
        name: 'No operational tool',
        verdict: RailVerdict.pass,
        detail: 'Nothing in the allowlist can pay, sign, place an order, or contact the counterparty. A person approves those actions.',
      ),
    ];

    return AgentRun(
      caseId: engagement.id,
      policyId: AgentRun.policyIdValue,
      steps: execution.steps,
      retrieved: execution.retrieved,
      judgments: execution.judgments,
      report: output.report,
      control: ControlRecord(
        principalId: who.id,
        loop: loop,
        reason: reason,
        standard: standard,
        escalated: escalated,
        guardrails: rails,
        audit: gate.audit,
        toolCalls: gate.used,
        toolBudget: gate.budget,
        batched: execution.batched && !escalated,
        approvalRequired: true,
        approvalNote: 'Approval is required before any operational or commercial action. This run only wrote a memo.',
        votes: execution.votes,
        quarantinedEvidenceIds: quarantined,
        restrictedEvidenceIds: restricted,
      ),
    );
  }

  AgentRun _blocked({
    required Engagement engagement,
    required Principal principal,
    required ToolGateway gate,
    required GuardrailCheck input,
    required List<String> quarantined,
    required List<String> restricted,
  }) {
    const report = InvestigationReport(
      headline: 'Input rail blocked the run',
      resolved: false,
      leadRiskId: null,
      confidence: 0,
      decisionNote: 'No search ran. The question did not clear the input rail.',
      recommendedAction: 'Rewrite the question as an diligence question, without an instruction override.',
      findings: [],
      competitors: [],
      gaps: ['The run stopped at the input rail.'],
      nextCollections: [],
      citedEvidenceIds: [],
    );
    return AgentRun(
      caseId: engagement.id,
      policyId: AgentRun.policyIdValue,
      steps: [
        AgentStep(
          id: 'input-rail',
          stage: AgentStage.scope,
          title: 'Input rail blocked the run',
          detail: input.detail,
        ),
      ],
      retrieved: const [],
      judgments: const [],
      report: report,
      control: ControlRecord(
        principalId: principal.id,
        loop: AgentLoopKind.planExecute,
        reason: 'The run never reached the router.',
        standard: 'Input guardrail. OWASP LLM01:2025. Block the turn before a tool call.',
        escalated: false,
        guardrails: [input],
        audit: gate.audit,
        toolCalls: 0,
        toolBudget: gate.budget,
        batched: false,
        approvalRequired: true,
        approvalNote: 'There is no memo to approve.',
        votes: const [],
        quarantinedEvidenceIds: quarantined,
        restrictedEvidenceIds: restricted,
      ),
    );
  }

  _Execution _runPlan(
    Engagement engagement,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final steps = <AgentStep>[];
    final byId = <String, RetrievalHit>{};
    steps.add(_scopeStep(engagement, 'Plan and execute'));
    for (var i = 0; i < engagement.plan.length; i++) {
      final planned = engagement.plan[i];
      final hits = _search(
        gate,
        index,
        engagement.id,
        RetrievalQuery(
          text: planned.text,
          modality: planned.modality,
          sourceKind: planned.sourceKind,
          limit: 8,
        ),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'retrieve-$i',
          stage: AgentStage.retrieve,
          title: planned.purpose,
          detail: _retrievalDetail(planned, hits),
          tool: 'search',
          query: planned.text,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
        ),
      );
    }
    _fillGaps(engagement, index, gate, byId, steps);
    _probeAll(engagement, index, gate, byId, steps);
    return _close(
      engagement,
      byId,
      steps,
      skip,
      batched: true,
      votes: const [],
    );
  }

  _Execution _runReact(
    Engagement engagement,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final steps = <AgentStep>[];
    final byId = <String, RetrievalHit>{};
    final seen = <String>{};
    steps.add(_scopeStep(engagement, 'ReAct'));
    final probed = <int>{};
    var guard = 0;
    while (guard < 16) {
      guard += 1;
      final missing = _missingModalities(engagement, byId.values);
      if (missing.isNotEmpty) {
        final modality = missing.first;
        final text = modality.replaceAll('-', ' ');
        if (!seen.add('gap:$text')) {
          break;
        }
        final hits = _search(
          gate,
          index,
          engagement.id,
          RetrievalQuery(text: text, modality: modality, limit: 8),
        );
        _absorb(byId, hits);
        steps.add(
          AgentStep(
            id: 'react-gap-$modality',
            stage: AgentStage.gap,
            title: 'Thought: $modality is still uncovered',
            detail: hits.isEmpty
                ? 'Action: search $text. Observation: nothing sealed came back. Stop asking this modality again.'
                : 'Action: search $text. Observation: ${hits.length} unit${hits.length == 1 ? '' : 's'}.',
            tool: 'search',
            query: text,
            evidenceIds: hits.map((hit) => hit.unit.id).toList(),
          ),
        );
        continue;
      }
      final next = _nextProbe(engagement, probed);
      if (next == null) {
        break;
      }
      probed.add(next);
      final risk = engagement.riskQuestions[next];
      final query = _probeQuery(risk);
      if (!seen.add('probe:$query')) {
        break;
      }
      final hits = _search(
        gate,
        index,
        engagement.id,
        RetrievalQuery(text: query, limit: 8),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'react-probe-$next',
          stage: AgentStage.retrieve,
          title: 'Thought: test ${risk.title}',
          detail:
              'Action: search support and falsifiers together. Observation: ${hits.length} hits.',
          tool: 'search',
          query: query,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
          riskProbe: true,
        ),
      );
    }
    final missing = _missingModalities(engagement, byId.values);
    steps.add(
      AgentStep(
        id: 'react-stop',
        stage: AgentStage.gap,
        title: 'Stop the loop',
        detail: missing.isEmpty
            ? 'Coverage is complete and every risk question has been probed. A repeated query would not be issued.'
            : 'Stopped with modalities still open: ${missing.join(', ')}.',
      ),
    );
    return _close(
      engagement,
      byId,
      steps,
      skip,
      batched: false,
      votes: const [],
    );
  }

  _Execution _runVote(
    Engagement engagement,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final planned = _runPlan(engagement, index, gate, skip);
    return _applyVote(engagement, planned, escalated: false);
  }

  _Execution _applyVote(
    Engagement engagement,
    _Execution execution, {
    required bool escalated,
  }) {
    final votes = [
      for (final seat in _seats)
        _vote(seat, engagement, execution.retrieved, execution.skip),
    ];
    final majority = _majority(votes);
    final lead = execution.report.leadRiskId;
    final top = execution.judgments.isEmpty ? null : execution.judgments.first;
    final unanimous =
        top != null &&
        top.net > 0 &&
        votes.every((vote) => vote.riskId == top.riskId);
    final InvestigationReport report;
    if (!escalated && majority != null && majority == lead) {
      final dissent = [
        for (final vote in votes)
          if (vote.riskId != majority)
            '${vote.seatTitle} seat dissented: ${vote.riskTitle}.',
      ];
      report = dissent.isEmpty
          ? execution.report
          : _withGaps(execution.report, dissent);
    } else if (escalated && unanimous) {
      report = _report(
        engagement: engagement,
        judgments: execution.judgments,
        missingModalities: execution.missing,
        panelCleared: true,
      );
    } else {
      report = _hold(
        execution.report,
        escalated
            ? 'After a thin ReAct margin the panel releases only on a unanimous strict lead. It did not reach one.'
            : majority == null
            ? 'The three seats did not produce a majority.'
            : 'The panel majority did not match a resolved lead, so the memo stays held.',
      );
    }
    final steps = [
      ...execution.steps,
      AgentStep(
        id: 'panel-vote',
        stage: AgentStage.adjudicate,
        title: 'Panel vote',
        detail: [
          for (final vote in votes)
            '${vote.seatTitle}: ${vote.riskTitle} '
                '(net ${vote.net.toStringAsFixed(2)}, margin ${vote.margin.toStringAsFixed(2)})',
          report.resolved ? 'Outcome: released.' : 'Outcome: held.',
        ].join('\n'),
      ),
    ];
    return _Execution(
      steps: steps,
      retrieved: execution.retrieved,
      judgments: execution.judgments,
      report: report,
      missing: execution.missing,
      votes: votes,
      batched: execution.batched,
      skip: execution.skip,
    );
  }

  SeatVote _vote(
    _Seat seat,
    Engagement engagement,
    List<RetrievalHit> retrieved,
    Set<String> skip,
  ) {
    final ranked = switch (seat.lens) {
      _Lens.plain => _rank(engagement, retrieved, skip),
      _Lens.falsifierWeighted => _rank(
        engagement,
        retrieved,
        skip,
        contradictScale: 2,
      ),
      _Lens.leaveOneOut => _rankLeaveOneOut(engagement, retrieved, skip),
    };
    final margin = _margin(ranked);
    if (ranked.isEmpty || ranked.first.net <= 0) {
      return SeatVote(
        seatId: seat.id,
        seatTitle: seat.title,
        riskId: null,
        riskTitle: 'No positive risk',
        net: ranked.isEmpty ? 0 : ranked.first.net,
        margin: margin,
      );
    }
    final lead = ranked.first;
    if (ranked.length > 1 && margin <= 0) {
      return SeatVote(
        seatId: seat.id,
        seatTitle: seat.title,
        riskId: null,
        riskTitle: 'Tie between ${lead.title} and ${ranked[1].title}',
        net: lead.net,
        margin: 0,
      );
    }
    return SeatVote(
      seatId: seat.id,
      seatTitle: seat.title,
      riskId: lead.riskId,
      riskTitle: lead.title,
      net: lead.net,
      margin: margin,
    );
  }

  List<RiskJudgment> _rankLeaveOneOut(
    Engagement engagement,
    List<RetrievalHit> retrieved,
    Set<String> skip,
  ) {
    final ranked = [
      for (final risk in engagement.riskQuestions)
        _weakest(risk, retrieved, skip),
    ]..sort(_byNet);
    return ranked;
  }

  /// The judgment for [risk] with whichever single supporting unit
  /// hurts it most when removed.
  RiskJudgment _weakest(
    RiskQuestion risk,
    List<RetrievalHit> retrieved,
    Set<String> skip,
  ) {
    var worst = scorer.judge(risk, retrieved, skip, 1);
    for (final hit in [...worst.supporting]) {
      final without = scorer.judge(risk, retrieved, {...skip, hit.unit.id}, 1);
      if (without.net < worst.net) {
        worst = without;
      }
    }
    return worst;
  }

  String? _majority(List<SeatVote> votes) {
    final counts = <String, int>{};
    for (final vote in votes) {
      final id = vote.riskId;
      if (id == null) {
        continue;
      }
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final winners = counts.entries.where((entry) => entry.value >= 2).toList();
    if (winners.length != 1) {
      return null;
    }
    return winners.first.key;
  }

  InvestigationReport _hold(InvestigationReport report, String note) {
    return InvestigationReport(
      headline: 'Panel did not clear the memo',
      resolved: false,
      leadRiskId: null,
      confidence: report.confidence.clamp(0.0, 0.4).toDouble(),
      decisionNote: note,
      recommendedAction:
          'Hold the decision until the seats agree or a person takes the case.',
      findings: report.findings,
      competitors: report.competitors,
      gaps: [...report.gaps, 'Panel majority failed.'],
      nextCollections: report.nextCollections,
      citedEvidenceIds: report.citedEvidenceIds,
    );
  }

  InvestigationReport _withGaps(
    InvestigationReport report,
    List<String> extra,
  ) {
    return InvestigationReport(
      headline: report.headline,
      resolved: report.resolved,
      leadRiskId: report.leadRiskId,
      confidence: report.confidence,
      decisionNote: report.decisionNote,
      recommendedAction: report.recommendedAction,
      findings: report.findings,
      competitors: report.competitors,
      gaps: [...report.gaps, ...extra],
      nextCollections: report.nextCollections,
      citedEvidenceIds: report.citedEvidenceIds,
    );
  }

  void _fillGaps(
    Engagement engagement,
    EvidenceIndex index,
    ToolGateway gate,
    Map<String, RetrievalHit> byId,
    List<AgentStep> steps,
  ) {
    final missing = _missingModalities(engagement, byId.values);
    for (var i = 0; i < missing.length; i++) {
      final modality = missing[i];
      final text = modality.replaceAll('-', ' ');
      final hits = _search(
        gate,
        index,
        engagement.id,
        RetrievalQuery(text: text, modality: modality, limit: 8),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'gap-fill-$i',
          stage: AgentStage.gap,
          title: 'Second pass for $modality',
          detail: hits.isEmpty
              ? 'No sealed $modality evidence answered the gap query.'
              : 'Gap query returned ${hits.length} $modality unit${hits.length == 1 ? '' : 's'}.',
          tool: 'search',
          query: text,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
        ),
      );
    }
  }

  void _probeAll(
    Engagement engagement,
    EvidenceIndex index,
    ToolGateway gate,
    Map<String, RetrievalHit> byId,
    List<AgentStep> steps,
  ) {
    for (var i = 0; i < engagement.riskQuestions.length; i++) {
      final risk = engagement.riskQuestions[i];
      final query = _probeQuery(risk);
      final hits = _search(
        gate,
        index,
        engagement.id,
        RetrievalQuery(text: query, limit: 8),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'probe-$i',
          stage: AgentStage.retrieve,
          title: 'Probe: ${risk.title}',
          detail: 'Look for support and falsifiers together, then score only what comes back.',
          tool: 'search',
          query: query,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
          riskProbe: true,
        ),
      );
    }
  }

  int? _nextProbe(Engagement engagement, Set<int> probed) {
    for (var i = 0; i < engagement.riskQuestions.length; i++) {
      if (!probed.contains(i)) {
        return i;
      }
    }
    return null;
  }

  List<RetrievalHit> _search(
    ToolGateway gate,
    EvidenceIndex index,
    String caseId,
    RetrievalQuery query,
  ) {
    final result = gate.call<List<RetrievalHit>>(
      tool: 'search',
      caseId: caseId,
      query: query.text,
      body: () => index.search(query),
    );
    return result.value ?? const [];
  }

  void _absorb(Map<String, RetrievalHit> byId, List<RetrievalHit> hits) {
    for (final hit in hits) {
      final prior = byId[hit.unit.id];
      if (prior == null || hit.score > prior.score) {
        byId[hit.unit.id] = hit;
      }
    }
  }

  _Execution _close(
    Engagement engagement,
    Map<String, RetrievalHit> byId,
    List<AgentStep> steps,
    Set<String> skip, {
    required bool batched,
    required List<SeatVote> votes,
  }) {
    final retrieved = byId.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) {
          return byScore;
        }
        return a.unit.id.compareTo(b.unit.id);
      });
    final missing = _missingModalities(engagement, retrieved);
    final judgments = _rank(engagement, retrieved, skip);
    steps.add(
      AgentStep(
        id: 'adjudicate',
        stage: AgentStage.adjudicate,
        title: 'Score the risk questions',
        detail: judgments
            .map(
              (judgment) =>
                  '${judgment.title}: net ${judgment.net.toStringAsFixed(2)} '
                  '(support ${judgment.supportScore.toStringAsFixed(2)}, '
                  'contradict ${judgment.contradictScore.toStringAsFixed(2)})',
            )
            .join('\n'),
        evidenceIds: {
          for (final judgment in judgments) ...[
            ...judgment.supporting.map((hit) => hit.unit.id),
            ...judgment.contradicting.map((hit) => hit.unit.id),
          ],
        }.toList(),
      ),
    );
    final report = _report(
      engagement: engagement,
      judgments: judgments,
      missingModalities: missing,
    );
    steps.add(
      AgentStep(
        id: 'report',
        stage: AgentStage.report,
        title: 'Write the decision memo',
        detail: report.decisionNote,
        evidenceIds: report.citedEvidenceIds,
      ),
    );
    return _Execution(
      steps: steps,
      retrieved: retrieved,
      judgments: judgments,
      report: report,
      missing: missing,
      votes: votes,
      batched: batched,
      skip: skip,
    );
  }

  double _margin(List<RiskJudgment> judgments) {
    if (judgments.isEmpty) {
      return 0;
    }
    if (judgments.length == 1) {
      return judgments.first.net;
    }
    return judgments.first.net - judgments[1].net;
  }

  AgentStep _scopeStep(Engagement engagement, String loop) {
    final criteria = engagement.decisionCriteria
        .map((item) => '• $item')
        .join('\n');
    return AgentStep(
      id: 'scope',
      stage: AgentStage.scope,
      title: 'Scope the question',
      detail:
          '${engagement.question}\n\nLoop: $loop.\n\nDecision criteria:\n$criteria',
    );
  }

  String _retrievalDetail(PlannedQuery planned, List<RetrievalHit> hits) {
    final filter = [
      if (planned.modality != null) 'modality=${planned.modality}',
      if (planned.sourceKind != null) 'source=${planned.sourceKind!.name}',
    ].join(', ');
    final suffix = filter.isEmpty ? '' : ' Filter: $filter.';
    if (hits.isEmpty) {
      return 'Search returned nothing.$suffix';
    }
    return 'Search returned ${hits.length} hit${hits.length == 1 ? '' : 's'}.$suffix';
  }

  List<String> _missingModalities(
    Engagement engagement,
    Iterable<RetrievalHit> hits,
  ) {
    final present = hits.map((hit) => hit.unit.modality).toSet();
    return [
      for (final modality in engagement.expectedModalities)
        if (!present.contains(modality)) modality,
    ];
  }

  List<RiskJudgment> _rank(
    Engagement engagement,
    List<RetrievalHit> retrieved,
    Set<String> skip, {
    double contradictScale = 1,
  }) {
    final ranked = [
      for (final risk in engagement.riskQuestions)
        scorer.judge(risk, retrieved, skip, contradictScale),
    ]..sort(_byNet);
    return ranked;
  }

  int _byNet(RiskJudgment a, RiskJudgment b) {
    final byNet = b.net.compareTo(a.net);
    if (byNet != 0) {
      return byNet;
    }
    return a.riskId.compareTo(b.riskId);
  }

  InvestigationReport _report({
    required Engagement engagement,
    required List<RiskJudgment> judgments,
    required List<String> missingModalities,
    bool panelCleared = false,
  }) {
    if (judgments.isEmpty) {
      return const InvestigationReport(
        headline: 'No risk questions were registered',
        resolved: false,
        leadRiskId: null,
        confidence: 0,
        decisionNote: 'The brief did not register risk questions to score.',
        recommendedAction: 'Register at least two risk questions before treating this as a decision.',
        findings: [],
        competitors: [],
        gaps: ['No risk catalog.'],
        nextCollections: [],
        citedEvidenceIds: [],
      );
    }

    final lead = judgments.first;
    final runnerUp = judgments.length > 1 ? judgments[1] : null;
    final margin = runnerUp == null ? lead.net : lead.net - runnerUp.net;
    final clearsBar = lead.net > 0 && margin >= _resolveMargin;
    final released = !clearsBar && panelCleared && lead.net > 0 && margin > 0;
    final resolved = clearsBar || released;
    final coverage = engagement.expectedModalities.isEmpty
        ? 1.0
        : (engagement.expectedModalities.length - missingModalities.length) /
              engagement.expectedModalities.length;
    final marginScore = margin <= 0 ? 0.0 : margin / (margin + 1.5);
    // No ceiling here on purpose. The output rail owns the 95% cap.
    final raw = resolved
        ? (0.2 + 0.75 * marginScore * coverage).clamp(0.0, 1.0).toDouble()
        : (0.15 * coverage).clamp(0.0, 0.4).toDouble();
    final confidence = released ? math.min(raw, _panelReleaseCap) : raw;

    final findings = <String>[];
    final cited = <String>{};
    for (final hit in lead.supporting.take(4)) {
      cited.add(hit.unit.id);
      findings.add('${hit.unit.title} [${hit.unit.id}]. ${hit.unit.text}');
    }
    if (findings.isEmpty) {
      findings.add(
        'No retrieved evidence carried a support phrase for the top risk.',
      );
    }

    final competitors = [
      for (final judgment in judgments.skip(resolved ? 1 : 0).take(3))
        _competitorLine(judgment),
    ];
    final gaps = <String>[
      if (missingModalities.isNotEmpty)
        'Missing modalities: ${missingModalities.join(', ')}.',
      if (!resolved && runnerUp != null)
        'Margin between ${lead.title} and ${runnerUp.title} is ${margin.toStringAsFixed(2)}, under the 0.45 resolve bar.',
      if (released)
        'Margin ${margin.toStringAsFixed(2)} is under the 0.45 bar. The memo was released only because all three seats agreed on a strict lead, and confidence is capped at 50%.',
      if (lead.missingSupport.isNotEmpty)
        'Lead risk still lacks: ${lead.missingSupport.join('; ')}.',
    ];
    if (gaps.isEmpty) {
      gaps.add(
        'No evidence gap is open. Residual risk is the runner-up, not a missing kind of record.',
      );
    }

    final next = <String>[];
    if (runnerUp != null && runnerUp.missingSupport.isNotEmpty) {
      next.add(
        'To give ${runnerUp.title} a fair chance, collect: ${runnerUp.missingSupport.take(3).join('; ')}.',
      );
    }
    if (missingModalities.isNotEmpty) {
      next.add(
        'Seal at least one observation for ${missingModalities.join(', ')}.',
      );
    }
    if (lead.contradicting.isEmpty && lead.matchedContradict.isEmpty) {
      next.add(
        'No falsifier for ${lead.title} was retrieved. A disconfirming sample would change the memo.',
      );
    }
    if (next.isEmpty) {
      next.add(
        'Repeat the decisive measurement with an independent instrument before acting.',
      );
    }

    final headline = resolved
        ? lead.title
        : 'No risk clears the evidence margin';
    final decisionNote = released
        ? '${lead.title} leads with net ${lead.net.toStringAsFixed(2)} on a thin margin of ${margin.toStringAsFixed(2)}. '
              'The panel released it unanimously after escalation, so confidence is capped at ${(confidence * 100).round()}%. '
              'The memo cites only ids retrieved in this run.'
        : resolved
        ? '${lead.title} leads with net ${lead.net.toStringAsFixed(2)}'
              '${runnerUp == null ? '' : ' against ${runnerUp.title} at ${runnerUp.net.toStringAsFixed(2)}'}. '
              'Confidence ${(confidence * 100).round()}% reflects that margin and modality coverage. '
              'The memo cites only ids retrieved in this run.'
        : 'The top risk, ${lead.title}, does not clear a positive net and a 0.45 margin. '
              'Hold the decision and collect the gaps below.';
    final recommendedAction = resolved
        ? lead.actionIfLead
        : 'Hold the decision. The evidence margin is too small to prefer one risk.';

    for (final judgment in judgments.take(2)) {
      for (final hit in [...judgment.supporting, ...judgment.contradicting]) {
        cited.add(hit.unit.id);
      }
    }

    final breakers = {
      for (final risk in engagement.riskQuestions)
        if (risk.dealBreaker) risk.id,
    };
    final triggered = [
      for (final judgment in judgments)
        if (breakers.contains(judgment.riskId) &&
            judgment.net >= _dealBreakerNet &&
            judgment.supporting.isNotEmpty)
          judgment.riskId,
    ];
    final leadOutcome = resolved
        ? engagement.riskQuestions
              .firstWhere((risk) => risk.id == lead.riskId)
              .outcome
        : Decision.hold;
    final decision = triggered.isNotEmpty ? Decision.walkAway : leadOutcome;
    final conditions = decision == Decision.proceedWithConditions
        ? [lead.actionIfLead]
        : const <String>[];

    return InvestigationReport(
      headline: headline,
      resolved: resolved,
      leadRiskId: resolved ? lead.riskId : null,
      decision: decision,
      triggeredDealBreakers: triggered,
      conditions: conditions,
      confidence: confidence,
      decisionNote: decisionNote,
      recommendedAction: recommendedAction,
      findings: findings,
      competitors: competitors,
      gaps: gaps,
      nextCollections: next.take(4).toList(),
      citedEvidenceIds: cited.toList()..sort(),
    );
  }

  String _competitorLine(RiskJudgment judgment) {
    final support = judgment.matchedSupport.isEmpty
        ? 'no support phrase hit'
        : 'support: ${judgment.matchedSupport.join(', ')}';
    final against = judgment.matchedContradict.isEmpty
        ? 'no falsifier hit'
        : 'falsified by: ${judgment.matchedContradict.join(', ')}';
    return '${judgment.title} (net ${judgment.net.toStringAsFixed(2)}). $support; $against.';
  }
}
