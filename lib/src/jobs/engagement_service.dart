import '../domain/models.dart';
import '../spec/models.dart';
import 'service_transport.dart';

/// One engagement the user made: its pinned spec version, the intake, and the
/// evidence. [spec] and [evidence] are empty in a list, and full after a get.
class UserEngagement {
  const UserEngagement({
    required this.id,
    required this.specId,
    required this.specVersion,
    required this.specHash,
    required this.dealType,
    required this.counterparty,
    required this.dealValue,
    required this.jurisdiction,
    required this.website,
    required this.context,
    required this.createdAt,
    this.evidenceCount = 0,
    this.spec,
    this.evidence = const [],
  });

  factory UserEngagement.fromJson(Map<String, Object?> json) {
    final pinned = json['spec'];
    return UserEngagement(
      id: json['id'] as String? ?? '',
      specId: json['spec_id'] as String? ?? '',
      specVersion: (json['spec_version'] as num?)?.toInt() ?? 1,
      specHash: json['spec_hash'] as String? ?? '',
      dealType: dealTypeFromWire(json['deal_type'] as String?),
      counterparty: json['counterparty'] as String? ?? '',
      dealValue: (json['deal_value'] as num?)?.toDouble() ?? 0,
      jurisdiction: json['jurisdiction'] as String? ?? '',
      website: json['website'] as String? ?? '',
      context: json['context'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.utc(2026, 1, 1),
      evidenceCount: (json['evidence_count'] as num?)?.toInt() ?? 0,
      spec: pinned is Map<String, Object?> ? StoredSpec.fromJson(pinned) : null,
      evidence: [
        for (final item in (json['evidence'] as List<Object?>? ?? const []))
          if (item is Map<String, Object?>) EngagementEvidence.fromJson(item),
      ],
    );
  }

  final String id;
  final String specId;
  final int specVersion;
  final String specHash;
  final DealType dealType;
  final String counterparty;
  final double dealValue;
  final String jurisdiction;
  final String website;
  final String context;
  final DateTime createdAt;
  final int evidenceCount;
  final StoredSpec? spec;
  final List<EngagementEvidence> evidence;
}

class EngagementEvidence {
  const EngagementEvidence({
    required this.id,
    required this.title,
    required this.source,
    required this.kind,
    required this.observedAt,
    required this.quarantined,
    this.text = '',
  });

  factory EngagementEvidence.fromJson(Map<String, Object?> json) =>
      EngagementEvidence(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        source: json['source'] as String? ?? '',
        kind: json['kind'] as String? ?? 'record',
        observedAt: json['observed_at'] as String? ?? '',
        quarantined: json['quarantined'] == true,
        text: json['text'] as String? ?? '',
      );

  final String id;
  final String title;
  final String source;
  final String kind;
  final String observedAt;
  final bool quarantined;
  final String text;
}

/// Saves the user's engagements and their evidence in the job service.
abstract interface class EngagementService {
  void setToken(String? token);

  Future<List<UserEngagement>> list();

  Future<UserEngagement> get(String id);

  Future<UserEngagement> create(Map<String, Object?> intake);

  Future<EngagementEvidence> addEvidence(
    String engagementId,
    Map<String, Object?> body,
  );

  Future<void> delete(String id);
}

class HttpEngagementService implements EngagementService {
  HttpEngagementService({ServiceTransport? transport})
    : _transport = transport ?? ServiceTransport(baseUrl: _defaultBaseUrl);

  static const _defaultBaseUrl = String.fromEnvironment(
    'JOBS_API',
    defaultValue: 'http://127.0.0.1:43124',
  );

  final ServiceTransport _transport;

  @override
  void setToken(String? token) => _transport.setToken(token);

  @override
  Future<List<UserEngagement>> list() async {
    final json = await _transport.send('GET', '/v1/engagements');
    final items = json['items'];
    if (items is! List<Object?>) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map<String, Object?>) UserEngagement.fromJson(item),
    ];
  }

  @override
  Future<UserEngagement> get(String id) async {
    return UserEngagement.fromJson(
      await _transport.send('GET', '/v1/engagements/$id'),
    );
  }

  @override
  Future<UserEngagement> create(Map<String, Object?> intake) async {
    return UserEngagement.fromJson(
      await _transport.send('POST', '/v1/engagements', body: intake),
    );
  }

  @override
  Future<EngagementEvidence> addEvidence(
    String engagementId,
    Map<String, Object?> body,
  ) async {
    return EngagementEvidence.fromJson(
      await _transport.send(
        'POST',
        '/v1/engagements/$engagementId/evidence',
        body: body,
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _transport.send('DELETE', '/v1/engagements/$id');
  }
}
