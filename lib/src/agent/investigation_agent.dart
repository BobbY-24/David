import '../domain/models.dart';
import '../retrieval/evidence_index.dart';
import '../retrieval/text_match.dart';

/// Offline investigation policy.
///
/// The run decomposes a case into scope, planned retrieval, a modality gap
/// pass, a probe for each competing explanation, adjudication, and a memo.
/// Scores use only evidence this run retrieved. Negated phrases do not count.
/// This is not a live language model.
class InvestigationAgent {
  const InvestigationAgent();

  AgentRun investigate(InvestigationCase caseFile) {
    final index = EvidenceIndex(caseFile.evidence);
    final steps = <AgentStep>[];
    final byId = <String, RetrievalHit>{};

    void absorb(List<RetrievalHit> hits) {
      for (final hit in hits) {
        final prior = byId[hit.unit.id];
        if (prior == null || hit.score > prior.score) {
          byId[hit.unit.id] = hit;
        }
      }
    }

    steps.add(
      AgentStep(
        id: 'scope',
        stage: AgentStage.scope,
        title: 'Scope the question',
        detail: _scopeDetail(caseFile),
      ),
    );

    for (var i = 0; i < caseFile.plan.length; i++) {
      final planned = caseFile.plan[i];
      final hits = index.search(
        RetrievalQuery(
          text: planned.text,
          modality: planned.modality,
          sourceKind: planned.sourceKind,
          limit: 8,
        ),
      );
      absorb(hits);
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

    final missingBeforeProbe = _missingModalities(caseFile, byId.values);
    for (var i = 0; i < missingBeforeProbe.length; i++) {
      final modality = missingBeforeProbe[i];
      final hits = index.search(
        RetrievalQuery(
          text: modality.replaceAll('-', ' '),
          modality: modality,
          limit: 8,
        ),
      );
      absorb(hits);
      steps.add(
        AgentStep(
          id: 'gap-fill-$i',
          stage: AgentStage.gap,
          title: 'Second pass for $modality',
          detail: hits.isEmpty
              ? 'No sealed $modality evidence answered the gap query.'
              : 'Gap query returned ${hits.length} $modality unit${hits.length == 1 ? '' : 's'}.',
          tool: 'search',
          query: modality.replaceAll('-', ' '),
          evidenceIds: hits.map((hit) => hit.unit.id).toList(),
        ),
      );
    }

    final missingAfter = _missingModalities(caseFile, byId.values);
    steps.add(
      AgentStep(
        id: 'gap-summary',
        stage: AgentStage.gap,
        title: 'Check modality coverage',
        detail: missingAfter.isEmpty
            ? 'Every modality named in the brief is present in the retrieved set.'
            : 'Still missing after the second pass: ${missingAfter.join(', ')}.',
      ),
    );

    for (var i = 0; i < caseFile.hypotheses.length; i++) {
      final hypothesis = caseFile.hypotheses[i];
      final phrases = [
        ...hypothesis.support.map((signature) => signature.phrase),
        ...hypothesis.contradict.map((signature) => signature.phrase),
      ];
      final query = phrases.join(' ');
      final hits = index.search(RetrievalQuery(text: query, limit: 8));
      absorb(hits);
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

    final retrieved = byId.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) {
          return byScore;
        }
        return a.unit.id.compareTo(b.unit.id);
      });

    final judgments =
        [
          for (final hypothesis in caseFile.hypotheses)
            _judge(hypothesis, retrieved),
        ]..sort((a, b) {
          final byNet = b.net.compareTo(a.net);
          if (byNet != 0) {
            return byNet;
          }
          return a.hypothesisId.compareTo(b.hypothesisId);
        });

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
      missingModalities: missingAfter,
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

    return AgentRun(
      caseId: caseFile.id,
      policyId: AgentRun.policyIdValue,
      steps: steps,
      retrieved: retrieved,
      judgments: judgments,
      report: report,
    );
  }

  String _scopeDetail(InvestigationCase caseFile) {
    final criteria = caseFile.decisionCriteria
        .map((item) => '• $item')
        .join('\n');
    final passes = caseFile.plan.map((item) => '• ${item.purpose}').join('\n');
    return '${caseFile.question}\n\nDecision criteria:\n$criteria\n\n'
        'Planned retrieval:\n$passes\n\n'
        'Required modalities: ${caseFile.expectedModalities.join(', ')}.';
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

  HypothesisJudgment _judge(
    HypothesisSpec hypothesis,
    List<RetrievalHit> retrieved,
  ) {
    final supporting = <RetrievalHit>[];
    final contradicting = <RetrievalHit>[];
    final matchedSupport = <String>[];
    final matchedContradict = <String>[];
    final missingSupport = <String>[];

    final supportScore = _scoreSignatures(
      signatures: hypothesis.support,
      retrieved: retrieved,
      into: supporting,
      matched: matchedSupport,
      missing: missingSupport,
    );
    final contradictScore = _scoreSignatures(
      signatures: hypothesis.contradict,
      retrieved: retrieved,
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
