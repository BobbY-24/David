import '../domain/models.dart';

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

/// Picks the loop from the shape of the engagement, before any search.
///
/// An acquisition moves price, escrow, or a walk-away, so it goes to a panel
/// vote. A brief that reports conflicting records, or needs six or more kinds
/// of evidence, goes to ReAct so the next search depends on what is missing.
/// Everything else is a checklist that runs as one batch (plan and execute).
class LoopRouter {
  const LoopRouter();

  static LoopDecision decide(Engagement engagement) {
    if (engagement.dealType == DealType.acquisition) {
      return const LoopDecision(
        kind: AgentLoopKind.panelVote,
        reason: 'The question moves price, escrow, or a walk-away, so one scorer is not enough.',
        standard: 'Panel vote. The analyst scores plainly, the robustness seat drops the strongest record behind each risk, and the skeptic doubles falsifiers. A majority is required and a tied seat abstains. Anthropic parallelization and voting.',
      );
    }
    final conflict = _recordsConflict(engagement);
    if (conflict || engagement.expectedModalities.length >= 6) {
      return LoopDecision(
        kind: AgentLoopKind.react,
        reason: conflict
            ? 'The brief reports conflicting records, so the next search depends on what is still missing.'
            : 'Six or more kinds of evidence are required, so coverage is checked one pass at a time.',
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

bool _recordsConflict(Engagement engagement) {
  final question = engagement.question.toLowerCase();
  return const [
    'conflict',
    'disagree',
    'inconsistent',
    'contradict',
  ].any(question.contains);
}
