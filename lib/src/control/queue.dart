import 'dart:async';
import 'dart:math' as math;

import '../agent/investigation_agent.dart';
import '../domain/models.dart';

class QueueRejection implements Exception {
  QueueRejection(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bounded worker lane for investigation runs.
///
/// The desk runs one case at a time. This lane is the throughput control for
/// a batch: a fixed number in flight, a queue cap, and no extra concurrency
/// when the cap is hit.
class InvestigationQueue {
  InvestigationQueue({
    this.maxInFlight = 2,
    this.maxQueued = 8,
    InvestigationAgent? agent,
  }) : _agent = agent ?? const InvestigationAgent();

  final int maxInFlight;
  final int maxQueued;
  final InvestigationAgent _agent;
  final Lane _lane = Lane();

  int get maxSeen => _lane.maxSeen;

  Future<List<AgentRun>> submit(List<InvestigationCase> cases) {
    final cap = maxInFlight + maxQueued;
    if (cases.length > cap) {
      throw QueueRejection(
        'Batch of ${cases.length} exceeds the lane cap of $cap. Submit a smaller batch.',
      );
    }
    _lane.limit = maxInFlight;
    return Future.wait(cases.map(_one));
  }

  Future<AgentRun> _one(InvestigationCase caseFile) async {
    await _lane.acquire();
    try {
      await Future<void>.delayed(Duration.zero);
      return _agent.investigate(caseFile);
    } finally {
      _lane.release();
    }
  }
}

class Lane {
  int limit = 1;
  int inFlight = 0;
  int maxSeen = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (inFlight < limit) {
      inFlight += 1;
      maxSeen = math.max(maxSeen, inFlight);
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future.then((_) {
      inFlight += 1;
      maxSeen = math.max(maxSeen, inFlight);
    });
  }

  void release() {
    inFlight -= 1;
    if (_waiters.isNotEmpty && inFlight < limit) {
      _waiters.removeAt(0).complete();
    }
  }
}
