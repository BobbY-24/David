import '../spec/models.dart';
import 'service_transport.dart';

/// Saves the user's agent specs and company profile in the job service.
abstract interface class SpecService {
  void setToken(String? token);

  Future<List<StoredSpec>> list();

  /// Starts a spec at version 1. The service picks its id.
  Future<StoredSpec> create(AgentSpec spec);

  /// Adds the next immutable version to an existing spec.
  Future<StoredSpec> addVersion(String specId, AgentSpec spec);

  Future<CompanyProfile> profile();

  Future<CompanyProfile> saveProfile(CompanyProfile profile);
}

class HttpSpecService implements SpecService {
  HttpSpecService({ServiceTransport? transport})
    : _transport = transport ?? ServiceTransport(baseUrl: _defaultBaseUrl);

  static const _defaultBaseUrl = String.fromEnvironment(
    'JOBS_API',
    defaultValue: 'http://127.0.0.1:43124',
  );

  final ServiceTransport _transport;

  @override
  void setToken(String? token) => _transport.setToken(token);

  @override
  Future<List<StoredSpec>> list() async {
    final json = await _transport.send('GET', '/v1/specs');
    final items = json['items'];
    if (items is! List<Object?>) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map<String, Object?>) StoredSpec.fromJson(item),
    ];
  }

  @override
  Future<StoredSpec> create(AgentSpec spec) async {
    final json = await _transport.send(
      'POST',
      '/v1/specs',
      body: {'spec': spec.toJson()},
    );
    return StoredSpec.fromJson(json);
  }

  @override
  Future<StoredSpec> addVersion(String specId, AgentSpec spec) async {
    final json = await _transport.send(
      'POST',
      '/v1/specs/$specId/versions',
      body: {'spec': spec.toJson()},
    );
    return StoredSpec.fromJson(json);
  }

  @override
  Future<CompanyProfile> profile() async {
    return CompanyProfile.fromJson(await _transport.send('GET', '/v1/profile'));
  }

  @override
  Future<CompanyProfile> saveProfile(CompanyProfile profile) async {
    return CompanyProfile.fromJson(
      await _transport.send('PUT', '/v1/profile', body: profile.toJson()),
    );
  }
}
