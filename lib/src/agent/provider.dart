import '../control/gateway.dart';
import '../domain/models.dart';
import 'engagement_agent.dart';

/// Where an engagement's reasoning comes from.
///
/// Every provider runs behind the same rails and gateway and must cite only
/// evidence its run retrieved. A model-backed provider holds its key in the
/// job service, never in this client.
abstract interface class EngagementProvider {
  /// Stable id recorded on every run.
  String get id;

  /// True when the provider never leaves this process.
  bool get offline;

  AgentRun run(Engagement engagement, {Principal? principal});
}

/// Offline, deterministic provider. It scores hand-written phrase signatures
/// over BM25 retrieval, so it needs no key and the tests can pin its output.
/// It is a demo of the control plane, not a model of diligence quality.
class DemoProvider implements EngagementProvider {
  const DemoProvider({this.agent = const EngagementAgent()});

  static const idValue = 'demo-provider';

  final EngagementAgent agent;

  @override
  String get id => idValue;

  @override
  bool get offline => true;

  @override
  AgentRun run(Engagement engagement, {Principal? principal}) {
    return agent.run(engagement, principal: principal);
  }
}
