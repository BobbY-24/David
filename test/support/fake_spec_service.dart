import 'package:david/src/jobs/spec_service.dart';
import 'package:david/src/spec/models.dart';

/// Keeps specs in memory. Never touches the network.
class FakeSpecService implements SpecService {
  final List<StoredSpec> stored = [];
  final List<AgentSpec> created = [];
  final List<(String, AgentSpec)> versions = [];
  final List<CompanyProfile> savedProfiles = [];
  CompanyProfile current = const CompanyProfile();
  String? token;

  @override
  void setToken(String? value) => token = value;

  @override
  Future<List<StoredSpec>> list() async => List.of(stored);

  @override
  Future<StoredSpec> create(AgentSpec spec) async {
    created.add(spec);
    final view = StoredSpec(
      specId: 'spec-${stored.length + 1}',
      version: 1,
      hash: 'a1b2c3d4${stored.length}',
      spec: spec,
    );
    stored.add(view);
    return view;
  }

  @override
  Future<StoredSpec> addVersion(String specId, AgentSpec spec) async {
    versions.add((specId, spec));
    final view = StoredSpec(
      specId: specId,
      version: 2,
      hash: 'e5f6a7b8',
      spec: spec,
    );
    stored.removeWhere((item) => item.specId == specId);
    stored.add(view);
    return view;
  }

  @override
  Future<CompanyProfile> profile() async => current;

  @override
  Future<CompanyProfile> saveProfile(CompanyProfile value) async {
    savedProfiles.add(value);
    current = value;
    return value;
  }
}
