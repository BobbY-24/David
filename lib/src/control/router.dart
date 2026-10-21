import '../domain/models.dart';
import '../retrieval/text_match.dart';

class LoopDecision {
  const LoopDecision({
    required this.kind,
    required this.reason,
    required this.standard,
  });

  final AgentLoopKind kind;
  final String reason;
  final String standard;
}

/// Picks the loop from the shape of the case, before any search.
///
/// Due diligence goes to a panel vote. A physical case whose next query
/// depends on coverage or a sensor conflict goes to ReAct. A short, already
/// decomposed brief stays on plan-and-execute so the searches can be batched.
class LoopRouter {
  const LoopRouter();

  static LoopDecision decide(InvestigationCase caseFile) {
    if (caseFile.kind == CaseKind.dueDiligence) {
      return const LoopDecision(
        kind: AgentLoopKind.panelVote,
        reason: 'The question moves price, escrow, or a walk-away, so one scorer is not enough.',
        standard: 'Panel vote. Operations scores plainly, measurement drops the strongest unit behind each explanation, and adversary doubles falsifiers. A majority is required and a tied seat abstains. Anthropic parallelization and voting; multi-agent voting when roles disagree.',
      );
    }
    final conflict = _sensorConflict(caseFile);
    if (conflict || caseFile.expectedModalities.length >= 6) {
      return LoopDecision(
        kind: AgentLoopKind.react,
        reason: conflict
            ? 'A sensor conflict is in the brief, so the next search depends on what is still missing.'
            : 'Six or more modalities are required, so coverage is checked one pass at a time.',
        standard: 'ReAct. Thought, search, observation, and a repeat stop. Yao et al. 2022. Used when the path is not fixed in advance.',
      );
    }
    return const LoopDecision(
      kind: AgentLoopKind.planExecute,
      reason: 'The brief already names the passes, and each search can run without waiting on the one before it.',
      standard: 'Plan and execute, in the ReWOO shape. Searches run as a batch, then one memo. Xu et al. 2023. Higher throughput than a thought between every call.',
    );
  }
}

bool _sensorConflict(InvestigationCase caseFile) {
  final question = caseFile.question.toLowerCase();
  if (question.contains('disagree') || question.contains('conflict')) {
    return true;
  }
  return caseFile.evidence.any(
    (unit) => phraseMatches(unit.searchableText, 'cameras disagree'),
  );
}
