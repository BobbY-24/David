import 'package:david/src/app.dart';
import 'package:david/src/ui/library_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_model_service.dart';
import 'support/fake_spec_service.dart';

Future<void> openLibrary(WidgetTester tester, FakeSpecService specs) async {
  tester.view.physicalSize = const Size(1440, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    DavidApp(modelService: FakeModelService(), specService: specs),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Library'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the library lists the six templates and a profile form', (
    tester,
  ) async {
    await openLibrary(tester, FakeSpecService());
    expect(find.text('START FROM A TEMPLATE'), findsOneWidget);
    expect(find.text('New wholesale customer'), findsOneWidget);
    expect(find.text('Contractor or freelancer business'), findsOneWidget);
    expect(find.text('Company profile'), findsOneWidget);
    expect(find.text('No specs yet'), findsOneWidget);
  });

  testWidgets('using a template and saving creates version 1 of a spec', (
    tester,
  ) async {
    final specs = FakeSpecService();
    await openLibrary(tester, specs);
    await tester.tap(find.text('Use').first);
    await tester.pumpAndSettle();
    expect(find.text('New spec from New wholesale customer'), findsOneWidget);

    await tester.ensureVisible(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();

    expect(specs.created, hasLength(1));
    expect(specs.created.single.name, 'New wholesale customer');
    expect(
      specs.created.single.risks.where((risk) => risk.dealBreaker),
      isNotEmpty,
    );
    expect(find.text('YOUR SPECS'), findsOneWidget);
    expect(find.text('New wholesale customer'), findsWidgets);
  });

  testWidgets(
    'a spec that breaks a rule is not sent, and the problem is shown',
    (tester) async {
      final specs = FakeSpecService();
      await openLibrary(tester, specs);
      await tester.tap(find.text('Use').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(libraryEditorNameKey), 'A');
      await tester.ensureVisible(find.byKey(libraryEditorSaveKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(libraryEditorSaveKey));
      await tester.pumpAndSettle();

      expect(specs.created, isEmpty);
      expect(find.textContaining('name of 2 to 120'), findsOneWidget);
    },
  );

  testWidgets('saving a new version of an existing spec appends a version', (
    tester,
  ) async {
    final specs = FakeSpecService();
    await openLibrary(tester, specs);
    await tester.tap(find.text('Use').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New version').first);
    await tester.pumpAndSettle();
    expect(find.text('Save new version'), findsOneWidget);
    await tester.ensureVisible(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(libraryEditorSaveKey));
    await tester.pumpAndSettle();

    expect(specs.versions, hasLength(1));
    expect(specs.versions.single.$1, 'spec-1');
  });

  testWidgets('the company profile saves and refuses a bad currency', (
    tester,
  ) async {
    final specs = FakeSpecService();
    await openLibrary(tester, specs);

    final company = find.widgetWithText(TextField, 'Company name');
    await tester.enterText(company, 'Acme Co');
    await tester.ensureVisible(find.byKey(libraryProfileSaveKey));
    await tester.tap(find.byKey(libraryProfileSaveKey));
    await tester.pumpAndSettle();
    expect(specs.savedProfiles.single.companyName, 'Acme Co');

    final currency = find.widgetWithText(TextField, 'Currency');
    await tester.enterText(currency, 'dollars');
    await tester.ensureVisible(find.byKey(libraryProfileSaveKey));
    await tester.tap(find.byKey(libraryProfileSaveKey));
    await tester.pumpAndSettle();
    expect(specs.savedProfiles, hasLength(1));
    expect(find.textContaining('three-letter code'), findsOneWidget);
  });

  testWidgets('the service token is passed to the spec client too', (
    tester,
  ) async {
    final specs = FakeSpecService();
    await openLibrary(tester, specs);
    expect(specs.token, isNull);
  });
}
