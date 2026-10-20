import 'package:fieldline/src/app.dart';
import 'package:fieldline/src/jobs/job_client.dart';
import 'package:fieldline/src/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desk opens on Harbor and a run produces the memo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DavidApp());
    expect(find.text('DAVID'), findsOneWidget);
    expect(find.text('Harbor Substation 4'), findsWidgets);
    expect(find.text('Run investigation'), findsOneWidget);

    await tester.tap(find.byKey(runInvestigationKey));
    await tester.pump();
    expect(find.text('Running…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Scope the question'), findsOneWidget);
    expect(find.textContaining('ReAct'), findsWidgets);

    await tester.ensureVisible(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allowlist and budget'), findsOneWidget);

    await tester.tap(find.text('Explanations'));
    await tester.pumpAndSettle();
    expect(find.text('Internal high-energy thermal fault'), findsOneWidget);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('FIELD MEMO'), findsOneWidget);
    expect(find.textContaining('Restrict T-2 load'), findsOneWidget);

    await tester.tap(find.text('Retrieve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(retrievalQueryKey), 'acetylene');
    await tester.tap(find.byKey(retrievalSearchKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('42 ppm'), findsWidgets);

    await tester.tap(find.text('Northline Logistics').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('revenue spike'), findsWidgets);
    expect(find.text('Scope the question'), findsNothing);
  });

  testWidgets('phone width can open observations and run a case', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DavidApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Observations'));
    await tester.pumpAndSettle();
    expect(find.text('IR camera A bushing temperature'), findsOneWidget);

    await tester.tap(find.text('Run investigation'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Scope the question'), findsOneWidget);

    await tester.ensureVisible(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('FIELD MEMO'), findsOneWidget);

    await tester.ensureVisible(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Job service unreachable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jobs tab enqueues a book against a fake service', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(DavidApp(jobClient: _FakeJobs()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Cedar book'), findsOneWidget);
    expect(find.text('40 ms'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('enqueue-Cedar book')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No order was sent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeJobs implements JobClient {
  ServiceJob? last;

  @override
  Future<ServiceBoard> board() async {
    return const ServiceBoard(
      ok: true,
      items: [
        CatalogItem(
          kind: 'portfolio',
          title: 'Cedar book',
          blurb: 'SQL positions and prices. No order is placed.',
          spec: {'account': 'cedar'},
        ),
      ],
      depth: 0,
      succeeded: 4,
      dead: 0,
      throughput: 0.2,
      waitP95: 8,
      e2eP95: 40,
      e2eP99: 55,
    );
  }

  @override
  Future<ServiceJob> enqueue({
    required String kind,
    required Map<String, Object?> spec,
    required String idempotencyKey,
  }) async {
    last = ServiceJob(
      id: 'job-1',
      status: 'succeeded',
      kind: kind,
      attempts: 1,
      headline: 'NVDA is 53% of Cedar, over the 25% cap. No order was sent.',
      detail: 'Weights come from the positions and prices tables.',
      queueWaitMs: 12,
      e2eMs: 40,
    );
    return last!;
  }

  @override
  Future<ServiceJob> fetch(String id) async => last!;
}
