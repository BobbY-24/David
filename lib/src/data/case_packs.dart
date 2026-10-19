import '../domain/models.dart';
import 'harbor_case.dart';
import 'northline_case.dart';
import 'vault_case.dart';

/// Synthetic investigation fixtures.
///
/// Readings, names, and seals are invented so the desk can show a full
/// workflow without pointing at a real site or a real transaction.
class CasePacks {
  static final List<InvestigationCase> all = [
    harborCase(),
    northlineCase(),
    vaultCase(),
  ];

  static InvestigationCase byId(String id) {
    return all.firstWhere((item) => item.id == id);
  }
}
