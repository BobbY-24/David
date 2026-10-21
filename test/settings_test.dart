import 'package:david/src/app.dart';
import 'package:david/src/jobs/model_service.dart';
import 'package:david/src/ui/settings_view.dart';
import 'package:david/src/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_model_service.dart';

const secret = 'sk-ant-api03-SECRETVALUEabcdefghij1234';

Future<void> openSettings(WidgetTester tester, FakeModelService service) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(DavidApp(modelService: service));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

TextField keyField(WidgetTester tester) {
  return tester.widget<TextField>(find.byKey(settingsKeyFieldKey));
}

Future<void> saveSecret(WidgetTester tester) async {
  await tester.enterText(find.byKey(settingsKeyFieldKey), secret);
  await tester.tap(find.byKey(settingsSaveKey));
  await tester.pumpAndSettle();
}

ModelJudgment brightlineJudgment(String model) {
  return judgmentOf({
    'delivery-reliability': {'b-reviews': 2.4, 'b-ontime-3': 2.0},
  }, model: model);
}

void main() {
  testWidgets('with no key the field is masked and runs stay on the demo', (
    tester,
  ) async {
    await openSettings(tester, FakeModelService());
    expect(find.text('No key saved'), findsOneWidget);
    final field = keyField(tester);
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(find.text('How your key is protected'), findsOneWidget);
    expect(find.text('Run diligence'), findsOneWidget);
  });

  testWidgets('saving clears the field and shows only the last four', (
    tester,
  ) async {
    final service = FakeModelService();
    await openSettings(tester, service);
    await saveSecret(tester);

    expect(service.savedKeys, [secret]);
    expect(keyField(tester).controller!.text, isEmpty);
    expect(find.textContaining('••••1234'), findsOneWidget);
    expect(find.textContaining('SECRETVALUE'), findsNothing);
    expect(find.textContaining(secret), findsNothing);
    expect(find.byType(EditableText), findsWidgets);
    expect(find.text('Run with Claude'), findsOneWidget);
  });

  testWidgets(
    'a run with the key is labelled as Claude and uses the chosen model',
    (tester) async {
      final service = FakeModelService(
        script: (_, _, model) => brightlineJudgment(model),
      );
      await openSettings(tester, service);
      await saveSecret(tester);

      await tester.ensureVisible(find.byKey(settingsModelKey));
      await tester.tap(find.byKey(settingsModelKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Claude Sonnet 5.5 · faster, lower cost').last,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(runDiligenceKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(service.judgeCalls, 1);
      expect(service.lastModel, 'claude-sonnet-5-5');
      // The agent header names the model; the step itself is in the provider test.
      expect(find.textContaining('· claude-sonnet-5-5'), findsOneWidget);
      expect(find.textContaining(secret), findsNothing);

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(find.text('DECISION MEMO'), findsOneWidget);
      expect(
        find.textContaining('weighed the evidence on your key'),
        findsOneWidget,
      );
      expect(find.textContaining('did not call a live model'), findsNothing);
    },
  );

  testWidgets('removing the key returns to the offline demo', (tester) async {
    final service = FakeModelService(
      initial: vaultStatus(configured: true, last4: '1234'),
    );
    await openSettings(tester, service);
    expect(find.textContaining('••••1234'), findsOneWidget);
    await tester.tap(find.byKey(settingsRemoveKey));
    await tester.pumpAndSettle();
    expect(find.text('No key saved'), findsOneWidget);
    expect(find.text('Run diligence'), findsOneWidget);
    expect(find.byKey(settingsRemoveKey), findsNothing);
  });

  testWidgets('a rejected key shows the reason and leaves nothing behind', (
    tester,
  ) async {
    final service = FakeModelService()
      ..saveError = const ModelServiceException(
        'key_rejected',
        'Anthropic rejected this key.',
      );
    await openSettings(tester, service);
    await saveSecret(tester);

    expect(find.text('Anthropic rejected this key.'), findsOneWidget);
    expect(keyField(tester).controller!.text, isEmpty);
    expect(find.textContaining('SECRETVALUE'), findsNothing);
    expect(find.text('Run diligence'), findsOneWidget);
  });

  testWidgets('an unreachable service is explained', (tester) async {
    final service = FakeModelService()
      ..statusError = const ModelServiceException(
        'service_unreachable',
        'The job service is not reachable. Start it to use your own key.',
      );
    await openSettings(tester, service);
    expect(find.text('Job service unreachable'), findsOneWidget);
    expect(find.textContaining('Start it to use your own key'), findsOneWidget);
  });

  testWidgets('a saved key that cannot be read asks for it again', (
    tester,
  ) async {
    final service = FakeModelService(
      initial: vaultStatus(configured: true, readable: false, last4: '1234'),
    );
    await openSettings(tester, service);
    expect(find.text('Saved key cannot be read'), findsOneWidget);
    expect(find.text('Run diligence'), findsOneWidget);
  });

  testWidgets('an unavailable vault says why', (tester) async {
    final service = FakeModelService(
      initial: vaultStatus(
        ready: false,
        reason: 'The data directory is not writable.',
      ),
    );
    await openSettings(tester, service);
    expect(find.text('Key vault unavailable'), findsOneWidget);
    expect(find.textContaining('not writable'), findsOneWidget);
  });

  testWidgets('the service token is applied in memory only', (tester) async {
    final service = FakeModelService();
    await openSettings(tester, service);
    await tester.tap(find.text('Advanced · service token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(settingsTokenFieldKey), 's3cret');
    await tester.ensureVisible(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(service.tokens, ['s3cret']);
  });

  testWidgets('phone width can reach Settings', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DavidApp(modelService: FakeModelService()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('No key saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
