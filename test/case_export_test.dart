import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_cases.dart';

void main() {
  test('the service fixture file matches the desk case packs', () {
    final onDisk = File(exportPath).readAsStringSync();
    expect(
      onDisk,
      encodeExport(),
      reason:
          'Run `dart run tool/export_cases.dart` after editing lib/src/data/.',
    );
  });
}
