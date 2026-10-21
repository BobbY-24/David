import 'package:david/src/jobs/engagement_service.dart';
import 'package:david/src/spec/models.dart';

/// Keeps engagements in memory. Never touches the network.
class FakeEngagementService implements EngagementService {
  FakeEngagementService(this.specs);

  final List<StoredSpec> specs;
  final Map<String, UserEngagement> _engagements = {};
  final Map<String, List<EngagementEvidence>> _evidence = {};
  String? token;
  int _counter = 0;

  @override
  void setToken(String? value) => token = value;

  UserEngagement _with(UserEngagement e, List<EngagementEvidence> units) {
    return UserEngagement(
      id: e.id,
      specId: e.specId,
      specVersion: e.specVersion,
      specHash: e.specHash,
      dealType: e.dealType,
      counterparty: e.counterparty,
      dealValue: e.dealValue,
      jurisdiction: e.jurisdiction,
      website: e.website,
      context: e.context,
      createdAt: e.createdAt,
      evidenceCount: units.length,
      spec: e.spec,
      evidence: units,
    );
  }

  @override
  Future<List<UserEngagement>> list() async => [
    for (final e in _engagements.values) _with(e, const []),
  ];

  @override
  Future<UserEngagement> get(String id) async =>
      _with(_engagements[id]!, List.of(_evidence[id]!));

  @override
  Future<UserEngagement> create(Map<String, Object?> intake) async {
    final spec = specs.firstWhere((s) => s.specId == intake['spec_id']);
    _counter += 1;
    final id = 'eng$_counter';
    _engagements[id] = UserEngagement(
      id: id,
      specId: spec.specId,
      specVersion: spec.version,
      specHash: spec.hash,
      dealType: spec.spec.dealType,
      counterparty: intake['counterparty'] as String,
      dealValue: (intake['deal_value'] as num).toDouble(),
      jurisdiction: '',
      website: '',
      context: '',
      createdAt: DateTime.utc(2026, 10, 1),
      spec: spec,
    );
    _evidence[id] = [];
    return get(id);
  }

  @override
  Future<EngagementEvidence> addEvidence(
    String engagementId,
    Map<String, Object?> body,
  ) async {
    _counter += 1;
    final text = body['text'] as String;
    final unit = EngagementEvidence(
      id: 'unit$_counter',
      title: body['title'] as String,
      source: body['source'] as String? ?? '',
      kind: body['kind'] as String? ?? 'record',
      observedAt: body['observed_at'] as String? ?? '',
      // The real service decides this with the same patterns the desk uses.
      quarantined: text.toLowerCase().contains('ignore previous'),
      text: text,
    );
    _evidence[engagementId]!.add(unit);
    return unit;
  }

  @override
  Future<void> delete(String id) async {
    _engagements.remove(id);
    _evidence.remove(id);
  }
}
