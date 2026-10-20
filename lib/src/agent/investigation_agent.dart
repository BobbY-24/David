import '../control/gateway.dart';
import '../control/rails.dart';
import '../control/router.dart';
import '../domain/models.dart';
import '../retrieval/evidence_index.dart';
import '../retrieval/text_match.dart';

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
  final List<HypothesisJudgment> judgments;
  final InvestigationReport report;
  final List<String> missing;
  final List<SeatVote> votes;
  final bool batched;
  final Set<String> skip;
}

class _Seat {
  const _Seat(this.id, this.title, this.supportScale);

  final String id;
  final String title;
  final Map<String, double> supportScale;
}

const _seats = <_Seat>[
  _Seat('operations', 'Operations', {}),
  _Seat('measurement', 'Measurement', {
    'telematics-defect': 1.25,
    'calibration-drift': 1.25,
    'logger-fault': 1.25,
  }),
  _Seat('adversary', 'Adversary', {
    'related-party-round-trip': 1.2,
    'channel-stuffing': 1.05,
    'internal-thermal-fault': 1.1,
  }),
];

/// Investigation entrypoint.
///
/// The router picks plan-and-execute, ReAct, or a panel vote. Every search
/// goes through [ToolGateway]. Rails run before the first search and after
/// the memo. The scorer still cites only retrieved ids.
class InvestigationAgent {
  const InvestigationAgent();

  AgentRun investigate(InvestigationCase caseFile, {Principal? principal}) {
    final who = principal ?? Principal.deskOperator(caseFile.id);
    final gate = ToolGateway(principal: who);
    final quarantined = [
      for (final unit in caseFile.evidence)
        if (containsInstructionOverride(unit.searchableText)) unit.id,
    ];
    final restricted = [
      for (final unit in caseFile.evidence)
        if (isRestricted(unit)) unit.id,
    ]..sort();
    final input = InputScreen.screen(
      question: caseFile.question,
      granted: who.grants(caseFile.id),
    );
    if (!input.allowed) {
      return _blocked(
        caseFile: caseFile,
        principal: who,
        gate: gate,
        input: input.check,
        quarantined: quarantined,
        restricted: restricted,
      );
    }

    final decision = LoopRouter.decide(caseFile);
    final index = EvidenceIndex(caseFile.evidence);
    final skip = quarantined.toSet();
    var execution = switch (decision.kind) {
      AgentLoopKind.planExecute => _runPlan(caseFile, index, gate, skip),
      AgentLoopKind.react => _runReact(caseFile, index, gate, skip),
      AgentLoopKind.panelVote => _runVote(caseFile, index, gate, skip),
    };

    var loop = decision.kind;
    var reason = decision.reason;
    var standard = decision.standard;
    var escalated = false;
    if (decision.kind == AgentLoopKind.react &&
        _margin(execution.judgments) < 0.45) {
      escalated = true;
      loop = AgentLoopKind.panelVote;
      reason = 'ReAct left a margin under 0.45, so the same evidence was sent to the panel.';
      standard = 'Escalation. A thin ReAct margin is not a place to invent another search. The panel votes on the evidence already retrieved.';
      execution = _applyVote(caseFile, execution);
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
        verdict: RailVerdict.pass,
        detail: quarantined.isEmpty
            ? 'No retrieved unit contained an instruction override. ${restricted.length} restricted unit${restricted.length == 1 ? '' : 's'} stay in the case store. The audit log stores redacted queries.'
            : 'Quarantined ${quarantined.length} unit${quarantined.length == 1 ? '' : 's'} that tried to instruct the policy.',
      ),
      output.check,
      const GuardrailCheck(
        rail: 'action',
        name: 'No operational tool',
        verdict: RailVerdict.pass,
        detail: 'Nothing in the allowlist can re-energize equipment, release lots, or move money. A person approves those actions.',
      ),
    ];

    return AgentRun(
      caseId: caseFile.id,
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
    required InvestigationCase caseFile,
    required Principal principal,
    required ToolGateway gate,
    required GuardrailCheck input,
    required List<String> quarantined,
    required List<String> restricted,
  }) {
    const report = InvestigationReport(
      headline: 'Input rail blocked the run',
      resolved: false,
      leadHypothesisId: null,
      confidence: 0,
      decisionNote: 'No search ran. The question did not clear the input rail.',
      recommendedAction: 'Rewrite the question as an investigation ask, without an instruction override.',
      findings: [],
      competitors: [],
      gaps: ['The run stopped at the input rail.'],
      nextCollections: [],
      citedEvidenceIds: [],
    );
    return AgentRun(
      caseId: caseFile.id,
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
    InvestigationCase caseFile,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final steps = <AgentStep>[];
    final byId = <String, RetrievalHit>{};
    steps.add(_scopeStep(caseFile, 'Plan and execute'));
    for (var i = 0; i < caseFile.plan.length; i++) {
      final planned = caseFile.plan[i];
      final hits = _search(
        gate,
        index,
        caseFile.id,
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
    _fillGaps(caseFile, index, gate, byId, steps);
    _probeAll(caseFile, index, gate, byId, steps);
    return _close(caseFile, byId, steps, skip, batched: true, votes: const []);
  }

  _Execution _runReact(
    InvestigationCase caseFile,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final steps = <AgentStep>[];
    final byId = <String, RetrievalHit>{};
    final seen = <String>{};
    steps.add(_scopeStep(caseFile, 'ReAct'));
    final probed = <int>{};
    var guard = 0;
    while (guard < 16) {
      guard += 1;
      final missing = _missingModalities(caseFile, byId.values);
      if (missing.isNotEmpty) {
        final modality = missing.first;
        final text = modality.replaceAll('-', ' ');
        if (!seen.add('gap:$text')) {
          break;
        }
        final hits = _search(
          gate,
          index,
          caseFile.id,
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
      final next = _nextProbe(caseFile, probed);
      if (next == null) {
        break;
      }
      probed.add(next);
      final hypothesis = caseFile.hypotheses[next];
      final query = [
        ...hypothesis.support.map((signature) => signature.phrase),
        ...hypothesis.contradict.map((signature) => signature.phrase),
      ].join(' ');
      if (!seen.add('probe:$query')) {
        break;
      }
      final hits = _search(
        gate,
        index,
        caseFile.id,
        RetrievalQuery(text: query, limit: 8),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'react-probe-$next',
          stage: AgentStage.retrieve,
          title: 'Thought: test ${hypothesis.title}',
          detail:
              'Action: search support and falsifiers together. Observation: ${hits.length} hits.',
          tool: 'search',
          query: query,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
          hypothesisProbe: true,
        ),
      );
    }
    final missing = _missingModalities(caseFile, byId.values);
    steps.add(
      AgentStep(
        id: 'react-stop',
        stage: AgentStage.gap,
        title: 'Stop the loop',
        detail: missing.isEmpty
            ? 'Coverage is complete and every explanation has been probed. A repeated query would not be issued.'
            : 'Stopped with modalities still open: ${missing.join(', ')}.',
      ),
    );
    return _close(caseFile, byId, steps, skip, batched: false, votes: const []);
  }

  _Execution _runVote(
    InvestigationCase caseFile,
    EvidenceIndex index,
    ToolGateway gate,
    Set<String> skip,
  ) {
    final planned = _runPlan(caseFile, index, gate, skip);
    return _applyVote(caseFile, planned);
  }

  _Execution _applyVote(InvestigationCase caseFile, _Execution execution) {
    final votes = [
      for (final seat in _seats)
        _vote(seat, caseFile, execution.retrieved, execution.skip),
    ];
    final majority = _majority(votes);
    final lead = execution.report.leadHypothesisId;
    final report = majority != null && majority == lead
        ? execution.report
        : _hold(
            execution.report,
            majority == null ? 'The three seats did not produce a majority.' : 'The panel majority did not match a resolved lead, so the memo stays held.',
          );
    final steps = [
      ...execution.steps,
      AgentStep(
        id: 'panel-vote',
        stage: AgentStage.adjudicate,
        title: 'Panel vote',
        detail: votes
            .map(
              (vote) =>
                  '${vote.seatTitle}: ${vote.hypothesisTitle} (${vote.net.toStringAsFixed(2)})',
            )
            .join('\n'),
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
    InvestigationCase caseFile,
    List<RetrievalHit> retrieved,
    Set<String> skip,
  ) {
    final ranked = _rank(caseFile, retrieved, skip, seat.supportScale);
    if (ranked.isEmpty || ranked.first.net <= 0) {
      return SeatVote(
        seatId: seat.id,
        seatTitle: seat.title,
        hypothesisId: null,
        hypothesisTitle: 'No positive explanation',
        net: ranked.isEmpty ? 0 : ranked.first.net,
      );
    }
    final lead = ranked.first;
    return SeatVote(
      seatId: seat.id,
      seatTitle: seat.title,
      hypothesisId: lead.hypothesisId,
      hypothesisTitle: lead.title,
      net: lead.net,
    );
  }

  String? _majority(List<SeatVote> votes) {
    final counts = <String, int>{};
    for (final vote in votes) {
      final id = vote.hypothesisId;
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
      leadHypothesisId: null,
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

  void _fillGaps(
    InvestigationCase caseFile,
    EvidenceIndex index,
    ToolGateway gate,
    Map<String, RetrievalHit> byId,
    List<AgentStep> steps,
  ) {
    final missing = _missingModalities(caseFile, byId.values);
    for (var i = 0; i < missing.length; i++) {
      final modality = missing[i];
      final text = modality.replaceAll('-', ' ');
      final hits = _search(
        gate,
        index,
        caseFile.id,
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
    InvestigationCase caseFile,
    EvidenceIndex index,
    ToolGateway gate,
    Map<String, RetrievalHit> byId,
    List<AgentStep> steps,
  ) {
    for (var i = 0; i < caseFile.hypotheses.length; i++) {
      final hypothesis = caseFile.hypotheses[i];
      final query = [
        ...hypothesis.support.map((signature) => signature.phrase),
        ...hypothesis.contradict.map((signature) => signature.phrase),
      ].join(' ');
      final hits = _search(
        gate,
        index,
        caseFile.id,
        RetrievalQuery(text: query, limit: 8),
      );
      _absorb(byId, hits);
      steps.add(
        AgentStep(
          id: 'probe-$i',
          stage: AgentStage.retrieve,
          title: 'Probe: ${hypothesis.title}',
          detail: 'Look for support and falsifiers together, then score only what comes back.',
          tool: 'search',
          query: query,
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
          hypothesisProbe: true,
        ),
      );
    }
  }

  int? _nextProbe(InvestigationCase caseFile, Set<int> probed) {
    for (var i = 0; i < caseFile.hypotheses.length; i++) {
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
    InvestigationCase caseFile,
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
    final missing = _missingModalities(caseFile, retrieved);
    final judgments = _rank(caseFile, retrieved, skip, const {});
    steps.add(
      AgentStep(
        id: 'adjudicate',
        stage: AgentStage.adjudicate,
        title: 'Score competing explanations',
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
      caseFile: caseFile,
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

  double _margin(List<HypothesisJudgment> judgments) {
    if (judgments.isEmpty) {
      return 0;
    }
    if (judgments.length == 1) {
      return judgments.first.net;
    }
    return judgments.first.net - judgments[1].net;
  }

  AgentStep _scopeStep(InvestigationCase caseFile, String loop) {
    final criteria = caseFile.decisionCriteria
        .map((item) => '• $item')
        .join('\n');
    return AgentStep(
      id: 'scope',
      stage: AgentStage.scope,
      title: 'Scope the question',
      detail:
          '${caseFile.question}\n\nLoop: $loop.\n\nDecision criteria:\n$criteria',
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
    InvestigationCase caseFile,
    Iterable<RetrievalHit> hits,
  ) {
    final present = hits.map((hit) => hit.unit.modality).toSet();
    return [
      for (final modality in caseFile.expectedModalities)
        if (!present.contains(modality)) modality,
    ];
  }

  List<HypothesisJudgment> _rank(
    InvestigationCase caseFile,
    List<RetrievalHit> retrieved,
    Set<String> skip,
    Map<String, double> supportScale,
  ) {
    final ranked =
        [
          for (final hypothesis in caseFile.hypotheses)
            _judge(
              hypothesis,
              retrieved,
              skip,
              supportScale[hypothesis.id] ?? 1,
            ),
        ]..sort((a, b) {
          final byNet = b.net.compareTo(a.net);
          if (byNet != 0) {
            return byNet;
          }
          return a.hypothesisId.compareTo(b.hypothesisId);
        });
    return ranked;
  }

  HypothesisJudgment _judge(
    HypothesisSpec hypothesis,
    List<RetrievalHit> retrieved,
    Set<String> skip,
    double supportScale,
  ) {
    final supporting = <RetrievalHit>[];
    final contradicting = <RetrievalHit>[];
    final matchedSupport = <String>[];
    final matchedContradict = <String>[];
    final missingSupport = <String>[];
    final usable = retrieved
        .where((hit) => !skip.contains(hit.unit.id))
        .toList();
    final supportScore =
        _scoreSignatures(
          signatures: hypothesis.support,
          retrieved: usable,
          into: supporting,
          matched: matchedSupport,
          missing: missingSupport,
        ) *
        supportScale;
    final contradictScore = _scoreSignatures(
      signatures: hypothesis.contradict,
      retrieved: usable,
      into: contradicting,
      matched: matchedContradict,
      missing: null,
    );
    return HypothesisJudgment(
      hypothesisId: hypothesis.id,
      title: hypothesis.title,
      statement: hypothesis.statement,
      actionIfLead: hypothesis.actionIfLead,
      supportScore: supportScore,
      contradictScore: contradictScore,
      net: supportScore - contradictScore,
      supporting: supporting,
      contradicting: contradicting,
      matchedSupport: matchedSupport,
      matchedContradict: matchedContradict,
      missingSupport: missingSupport,
    );
  }

  double _scoreSignatures({
    required List<Signature> signatures,
    required List<RetrievalHit> retrieved,
    required List<RetrievalHit> into,
    required List<String> matched,
    required List<String>? missing,
  }) {
    var total = 0.0;
    final seen = into.map((hit) => hit.unit.id).toSet();
    for (final signature in signatures) {
      RetrievalHit? best;
      for (final hit in retrieved) {
        if (!phraseMatches(hit.unit.searchableText, signature.phrase)) {
          continue;
        }
        if (best == null || hit.score > best.score) {
          best = hit;
        }
      }
      if (best == null) {
        missing?.add(signature.phrase);
        continue;
      }
      matched.add(signature.phrase);
      final norm = best.score / (best.score + 2.5);
      total += signature.weight * (0.65 + 0.35 * norm);
      if (seen.add(best.unit.id)) {
        into.add(best);
      }
    }
    return total;
  }

  InvestigationReport _report({
    required InvestigationCase caseFile,
    required List<HypothesisJudgment> judgments,
    required List<String> missingModalities,
  }) {
    if (judgments.isEmpty) {
      return const InvestigationReport(
        headline: 'No explanations were registered',
        resolved: false,
        leadHypothesisId: null,
        confidence: 0,
        decisionNote:
            'The brief did not register competing explanations to score.',
        recommendedAction: 'Register at least two explanations before treating this as a decision.',
        findings: [],
        competitors: [],
        gaps: ['No hypothesis catalog.'],
        nextCollections: [],
        citedEvidenceIds: [],
      );
    }

    final lead = judgments.first;
    final runnerUp = judgments.length > 1 ? judgments[1] : null;
    final margin = runnerUp == null ? lead.net : lead.net - runnerUp.net;
    final resolved = lead.net > 0 && margin >= 0.45;
    final coverage = caseFile.expectedModalities.isEmpty
        ? 1.0
        : (caseFile.expectedModalities.length - missingModalities.length) /
              caseFile.expectedModalities.length;
    final marginScore = margin <= 0 ? 0.0 : margin / (margin + 1.5);
    final confidence = resolved
        ? (0.2 + 0.75 * marginScore * coverage).clamp(0.0, 0.95).toDouble()
        : (0.15 * coverage).clamp(0.0, 0.4).toDouble();

    final findings = <String>[];
    final cited = <String>{};
    for (final hit in lead.supporting.take(4)) {
      cited.add(hit.unit.id);
      findings.add('${hit.unit.title} [${hit.unit.id}]. ${hit.unit.text}');
    }
    if (findings.isEmpty) {
      findings.add(
        'No retrieved evidence carried a support phrase for the top explanation.',
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
      if (lead.missingSupport.isNotEmpty)
        'Lead explanation still lacks: ${lead.missingSupport.join('; ')}.',
    ];
    if (gaps.isEmpty) {
      gaps.add(
        'No modality gap is open. Residual risk is the runner-up, not a missing sensor class.',
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
        : 'No explanation clears the evidence margin';
    final decisionNote = resolved
        ? '${lead.title} leads with net ${lead.net.toStringAsFixed(2)}'
              '${runnerUp == null ? '' : ' against ${runnerUp.title} at ${runnerUp.net.toStringAsFixed(2)}'}. '
              'Confidence ${(confidence * 100).round()}% reflects that margin and modality coverage. '
              'The memo cites only ids retrieved in this run.'
        : 'The top explanation, ${lead.title}, does not clear a positive net and a 0.45 margin. '
              'Hold the decision and collect the gaps below.';
    final recommendedAction = resolved
        ? lead.actionIfLead
        : 'Hold the decision. The evidence margin is too small to prefer one explanation.';

    for (final judgment in judgments.take(2)) {
      for (final hit in [...judgment.supporting, ...judgment.contradicting]) {
        cited.add(hit.unit.id);
      }
    }

    return InvestigationReport(
      headline: headline,
      resolved: resolved,
      leadHypothesisId: resolved ? lead.hypothesisId : null,
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

  String _competitorLine(HypothesisJudgment judgment) {
    final support = judgment.matchedSupport.isEmpty
        ? 'no support phrase hit'
        : 'support: ${judgment.matchedSupport.join(', ')}';
    final against = judgment.matchedContradict.isEmpty
        ? 'no falsifier hit'
        : 'falsified by: ${judgment.matchedContradict.join(', ')}';
    return '${judgment.title} (net ${judgment.net.toStringAsFixed(2)}). $support; $against.';
  }
}
