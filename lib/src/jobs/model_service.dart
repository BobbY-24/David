import 'package:http/http.dart' as http;

import '../agent/scorer.dart';
import 'service_transport.dart';

export 'service_transport.dart' show ModelServiceException;

/// What the desk may know about the saved key. The key itself is never sent
/// back by the service, only its last four characters.
class VaultStatus {
  const VaultStatus({
    required this.vaultReady,
    this.vaultReason,
    required this.configured,
    required this.readable,
    this.last4,
    this.savedAt,
    this.verifiedAt,
    this.calls = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cap = 0,
    this.models = const [],
    this.defaultModel = '',
  });

  factory VaultStatus.fromJson(Map<String, Object?> json) {
    final vault = _map(json['vault']);
    final key = _map(json['anthropic']);
    final usage = _map(json['usage']);
    return VaultStatus(
      vaultReady: vault['ready'] == true,
      vaultReason: vault['reason'] as String?,
      configured: key['configured'] == true,
      readable: key['readable'] != false,
      last4: key['last4'] as String?,
      savedAt: key['saved_at'] as String?,
      verifiedAt: key['verified_at'] as String?,
      calls: _int(usage['calls']),
      inputTokens: _int(usage['input_tokens']),
      outputTokens: _int(usage['output_tokens']),
      cap: _int(usage['cap']),
      models: [
        for (final model in (json['models'] as List<Object?>? ?? const []))
          model.toString(),
      ],
      defaultModel: json['default_model'] as String? ?? '',
    );
  }

  final bool vaultReady;
  final String? vaultReason;
  final bool configured;
  final bool readable;
  final String? last4;
  final String? savedAt;
  final String? verifiedAt;
  final int calls;
  final int inputTokens;
  final int outputTokens;
  final int cap;
  final List<String> models;
  final String defaultModel;

  /// A key is saved and can be decrypted, so a run may use it.
  bool get usable => configured && readable;
}

/// A model's weights for every risk question, plus what the call cost.
class ModelJudgment {
  const ModelJudgment({
    required this.model,
    required this.risks,
    required this.inputTokens,
    required this.outputTokens,
  });

  final String model;
  final List<ModelRiskScore> risks;
  final int inputTokens;
  final int outputTokens;
}

/// Asks the job service to score an engagement with the user's saved key.
abstract interface class ModelJudge {
  Future<ModelJudgment> judge({
    required String engagementId,
    required List<String> evidenceIds,
    required String model,
  });
}

/// The key vault plus the model route, as the desk sees them.
abstract interface class ModelService implements ModelJudge {
  Future<VaultStatus> status();

  /// Sends the key to the service once. Nothing here keeps it.
  Future<VaultStatus> saveKey(String key);

  Future<VaultStatus> verifyKey();

  Future<VaultStatus> removeKey();

  /// Optional shared secret for services started with DAVID_API_TOKEN. Held in
  /// memory only.
  void setToken(String? token);
}

class HttpModelService implements ModelService {
  HttpModelService({http.Client? httpClient, String? baseUrl})
    : _transport = ServiceTransport(
        httpClient: httpClient,
        baseUrl:
            baseUrl ??
            const String.fromEnvironment(
              'JOBS_API',
              defaultValue: 'http://127.0.0.1:43124',
            ),
      );

  static const _shortTimeout = Duration(seconds: 20);
  static const _modelTimeout = Duration(seconds: 180);

  final ServiceTransport _transport;

  @override
  void setToken(String? token) => _transport.setToken(token);

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = _shortTimeout,
  }) => _transport.send(method, path, body: body, timeout: timeout);

  @override
  Future<VaultStatus> status() async {
    return VaultStatus.fromJson(await _send('GET', '/v1/vault'));
  }

  @override
  Future<VaultStatus> saveKey(String key) async {
    return VaultStatus.fromJson(
      await _send('PUT', '/v1/vault/anthropic', body: {'key': key}),
    );
  }

  @override
  Future<VaultStatus> verifyKey() async {
    return VaultStatus.fromJson(
      await _send('POST', '/v1/vault/anthropic/verify'),
    );
  }

  @override
  Future<VaultStatus> removeKey() async {
    return VaultStatus.fromJson(await _send('DELETE', '/v1/vault/anthropic'));
  }

  @override
  Future<ModelJudgment> judge({
    required String engagementId,
    required List<String> evidenceIds,
    required String model,
  }) async {
    final json = await _send(
      'POST',
      '/v1/model/judge',
      body: {
        'engagement_id': engagementId,
        'evidence_ids': evidenceIds,
        'model': model,
      },
      timeout: _modelTimeout,
    );
    final usage = _map(json['usage']);
    return ModelJudgment(
      model: json['model'] as String? ?? model,
      risks: [
        for (final item in (json['risks'] as List<Object?>? ?? const []))
          if (item is Map<String, Object?>) _risk(item),
      ],
      inputTokens: _int(usage['input_tokens']),
      outputTokens: _int(usage['output_tokens']),
    );
  }

  ModelRiskScore _risk(Map<String, Object?> json) {
    List<ModelEvidenceWeight> entries(Object? raw) => [
      for (final item in (raw as List<Object?>? ?? const []))
        if (item is Map<String, Object?> &&
            item['evidence_id'] is String &&
            item['weight'] is num)
          ModelEvidenceWeight(
            evidenceId: item['evidence_id']! as String,
            weight: (item['weight']! as num).toDouble(),
            note: item['note'] as String? ?? '',
          ),
    ];
    return ModelRiskScore(
      riskId: json['risk_id'] as String? ?? '',
      support: entries(json['support']),
      contradict: entries(json['contradict']),
    );
  }
}

Map<String, Object?> _map(Object? value) {
  return value is Map<String, Object?> ? value : const {};
}

int _int(Object? value) => value is num ? value.toInt() : 0;
