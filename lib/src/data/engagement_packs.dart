import '../domain/models.dart';
import 'brightline_case.dart';
import 'corvid_case.dart';
import 'northline_case.dart';

/// Synthetic due-diligence fixtures.
///
/// Companies, people, records, and seals are invented so the desk can show a
/// full workflow without pointing at a real business or transaction.
class EngagementPacks {
  static final List<Engagement> all = [
    brightlineCase(),
    corvidCase(),
    northlineCase(),
  ];

  static Engagement byId(String id) {
    return all.firstWhere((item) => item.id == id);
  }
}
