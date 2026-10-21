import 'package:david/src/agent/scorer.dart';
import 'package:david/src/jobs/model_service.dart';

VaultStatus vaultStatus({
  bool ready = true,
  String? reason,
  bool configured = false,
  bool readable = true,
  String? last4,
  String? verifiedAt,
  int calls = 0,
}) {
  return VaultStatus(
    vaultReady: ready,
    vaultReason: reason,
    configured: configured,
    readable: readable,
    last4: last4,
    verifiedAt: verifiedAt,
    calls: calls,
    inputTokens: calls * 1200,
    outputTokens: calls * 600,
    cap: 100,
    models: const ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'],
    defaultModel: 'claude-opus-5-5',
  );
}

/// A scripted [ModelService]. It records what the desk sends and never
/// touches the network.
class FakeModelService implements ModelService {
  FakeModelService({VaultStatus? initial, this.script})
    : current = initial ?? vaultStatus();

  VaultStatus current;
  final ModelJudgment Function(
    String engagementId,
    List<String> evidenceIds,
    String model,
  )?
  script;
  final List<String> savedKeys = [];
  final List<String?> tokens = [];
  Object? statusError;
  Object? saveError;
  int judgeCalls = 0;
  List<String> lastEvidenceIds = const [];
  String? lastModel;
  String? lastEngagementId;

  @override
  void setToken(String? token) => tokens.add(token);

  @override
  Future<VaultStatus> status() async {
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return current;
  }

  @override
  Future<VaultStatus> saveKey(String key) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    savedKeys.add(key);
    current = vaultStatus(
      configured: true,
      last4: key.substring(key.length - 4),
      verifiedAt: '2026-10-20T14:00:00+00:00',
    );
    return current;
  }

  @override
  Future<VaultStatus> verifyKey() async => current;

  @override
  Future<VaultStatus> removeKey() async {
    current = vaultStatus();
    return current;
  }

  @override
  Future<ModelJudgment> judge({
    required String engagementId,
    required List<String> evidenceIds,
    required String model,
  }) async {
    judgeCalls += 1;
    lastEngagementId = engagementId;
    lastEvidenceIds = evidenceIds;
    lastModel = model;
    final run = script;
    if (run == null) {
      return ModelJudgment(
        model: model,
        risks: const [],
        inputTokens: 100,
        outputTokens: 50,
      );
    }
    return run(engagementId, evidenceIds, model);
  }
}

/// Builds a [ModelJudgment] from `{riskId: {evidenceId: weight}}` for support
/// and an optional second map for contradiction.
ModelJudgment judgmentOf(
  Map<String, Map<String, double>> support, {
  Map<String, Map<String, double>> contradict = const {},
  String model = 'claude-opus-5-5',
}) {
  final ids = {...support.keys, ...contradict.keys};
  List<ModelEvidenceWeight> entries(Map<String, double>? weights) => [
    for (final entry in (weights ?? const <String, double>{}).entries)
      ModelEvidenceWeight(
        evidenceId: entry.key,
        weight: entry.value,
        note: 'Because of ${entry.key}.',
      ),
  ];
  return ModelJudgment(
    model: model,
    risks: [
      for (final id in ids)
        ModelRiskScore(
          riskId: id,
          support: entries(support[id]),
          contradict: entries(contradict[id]),
        ),
    ],
    inputTokens: 1200,
    outputTokens: 600,
  );
}
