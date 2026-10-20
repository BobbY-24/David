import 'package:fieldline/src/app.dart';
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

    await tester.pumpWidget(const FieldlineApp());
    expect(find.text('FIELDLINE'), findsOneWidget);
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

    await tester.pumpWidget(const FieldlineApp());
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
    expect(tester.takeException(), isNull);
  });
}
