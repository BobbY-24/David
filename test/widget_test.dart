import 'package:david/src/app.dart';
import 'package:david/src/jobs/job_client.dart';
import 'package:david/src/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desk opens on Brightline and a run produces the memo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DavidApp());
    expect(find.text('DAVID'), findsOneWidget);
    expect(find.text('Brightline Supply'), findsWidgets);
    expect(find.text('Run diligence'), findsOneWidget);

    await tester.tap(find.byKey(runDiligenceKey));
    await tester.pump();
    expect(find.text('Running…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Scope the question'), findsOneWidget);
    expect(find.textContaining('Plan and execute'), findsWidgets);

    await tester.ensureVisible(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allowlist and budget'), findsOneWidget);

    await tester.tap(find.text('Risks'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery reliability risk'), findsWidgets);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('DECISION MEMO'), findsOneWidget);
    expect(find.textContaining('milestones'), findsWidgets);

    await tester.tap(find.text('Retrieve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(retrievalQueryKey), 'sanctions');
    await tester.tap(find.byKey(retrievalSearchKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('OFAC'), findsWidgets);

    await tester.tap(find.text('Northline Logistics').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('revenue spike'), findsWidgets);
    expect(find.text('Scope the question'), findsNothing);
  });

  testWidgets('phone width can open evidence and run an engagement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DavidApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();
    expect(find.text('On-time delivery rate'), findsWidgets);

    await tester.tap(find.text('Run diligence'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Scope the question'), findsOneWidget);

    await tester.ensureVisible(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('DECISION MEMO'), findsOneWidget);

    await tester.ensureVisible(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Job service unreachable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jobs tab enqueues an engagement against a fake service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(DavidApp(jobClient: _FakeJobs()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Brightline Supply'), findsWidgets);
    expect(find.text('40 ms'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('enqueue-Brightline Supply')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delivery reliability risk leads'),
      findsOneWidget,
    );
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
          kind: 'engagement',
          title: 'Brightline Supply',
          blurb: 'Vendor check scored by the demo scorer.',
          spec: {'case_id': 'brightline-supply'},
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
      headline: 'Delivery reliability risk leads Brightline Supply.',
      detail: 'Demo scorer. The desk agent remains the citation path.',
      queueWaitMs: 12,
      e2eMs: 40,
    );
    return last!;
  }

  @override
  Future<ServiceJob> fetch(String id) async => last!;
}
