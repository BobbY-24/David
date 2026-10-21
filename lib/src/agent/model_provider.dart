import '../control/gateway.dart';
import '../domain/models.dart';
import '../jobs/model_service.dart';
import 'engagement_agent.dart';
import 'provider.dart';
import 'scorer.dart';

/// Scores an engagement with the user's own Claude key.
///
/// The key lives only in the job service. This client never holds it: it sends
/// the ids of the evidence a run retrieved, the service reads their sealed text
/// and calls Claude, and the answer comes back as weights per risk question.
///
/// Two passes keep every existing guarantee:
///
/// 1. The offline agent retrieves through the tool gateway and the input rail.
///    If it was blocked, or retrieved nothing, no model call is made.
/// 2. The agent runs again with a [ModelScorer] built from the model's
///    weights. The router, the panel lenses, the escalation rule, the memo,
///    and the output rail all run on those weights, and an id the run did not
///    retrieve counts for nothing.
class ModelProvider implements EngagementProvider {
  ModelProvider({required this.judge, this.model = defaultModel});

  static const idValue = 'claude-provider';
  static const defaultModel = 'claude-opus-5-5';

  /// The service scores at most this many units per call, best match first.
  static const maxEvidence = 60;

  final ModelJudge judge;
  final String model;

  @override
  String get id => idValue;

  @override
  bool get offline => false;

  @override
  Future<AgentRun> runAsync(
    Engagement engagement, {
    Principal? principal,
  }) async {
    final first = const DemoProvider().run(engagement, principal: principal);
    if (first.retrieved.isEmpty) {
      return first;
    }
    final sent = first.retrieved.take(maxEvidence).toList();
    final retrievedIds = {for (final hit in sent) hit.unit.id};
    final judgment = await judge.judge(
      engagementId: engagement.id,
      evidenceIds: [for (final hit in sent) hit.unit.id],
      model: model,
    );
    final scores = [
      for (final risk in judgment.risks)
        ModelRiskScore(
          riskId: risk.riskId,
          support: _retrievedOnly(risk.support, retrievedIds),
          contradict: _retrievedOnly(risk.contradict, retrievedIds),
        ),
    ];
    final second = EngagementAgent(scorer: ModelScorer(scores))
        .run(engagement, principal: principal);
    return second.withModel(
      providerId: id,
      modelId: judgment.model,
      inputTokens: judgment.inputTokens,
      outputTokens: judgment.outputTokens,
      steps: _withModelStep(
        second.steps,
        scores,
        judgment,
        retrievedIds.length,
      ),
    );
  }

  List<ModelEvidenceWeight> _retrievedOnly(
    List<ModelEvidenceWeight> entries,
    Set<String> retrievedIds,
  ) {
    return [
      for (final entry in entries)
        if (retrievedIds.contains(entry.evidenceId)) entry,
    ];
  }

  List<AgentStep> _withModelStep(
    List<AgentStep> steps,
    List<ModelRiskScore> scores,
    ModelJudgment judgment,
    int retrieved,
  ) {
    final cited = <String>{
      for (final score in scores) ...[
        for (final entry in score.support) entry.evidenceId,
        for (final entry in score.contradict) entry.evidenceId,
      ],
    };
    final step = AgentStep(
      id: 'model-score',
      stage: AgentStage.adjudicate,
      title: 'Claude weighed the evidence',
      detail:
          '${judgment.model} read $retrieved retrieved units on your key and '
          'cited ${cited.length} of them across ${scores.length} risk '
          'questions (${judgment.inputTokens} tokens in, '
          '${judgment.outputTokens} out). It had no tools. The desk checked '
          'every cited id against this run and computed the decision from the '
          'weights.',
      evidenceIds: cited.toList()..sort(),
    );
    final at = steps.indexWhere((s) => s.id == 'adjudicate');
    if (at < 0) {
      return [...steps, step];
    }
    return [...steps.sublist(0, at), step, ...steps.sublist(at)];
  }
}
