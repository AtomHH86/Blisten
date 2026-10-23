import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/checked_hooks.dart';

/// Negative harness test. Every mode must make flutter drive exit nonzero.
/// Run explicitly with ABTS_HARNESS_FAILURE=setup|teardown|setup-timeout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const failure = String.fromEnvironment('ABTS_HARNESS_FAILURE');

  setUpAll(
    () => guardedHook(
      'harness setup',
      () async {
        expect(failure, isIn(['setup', 'teardown', 'setup-timeout']));
        if (failure == 'setup') {
          throw StateError('intentional harness setup failure');
        }
        if (failure == 'setup-timeout') {
          await Completer<void>().future;
        }
      },
      timeout: failure == 'setup-timeout'
          ? const Duration(milliseconds: 100)
          : const Duration(seconds: 25),
    ),
  );

  tearDownAll(
    () => guardedHook('harness teardown', () {
      if (failure == 'teardown') {
        throw StateError('intentional harness teardown failure');
      }
    }),
  );

  testWidgets('passing body does not hide hook failures', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('body passed')));
    expect(find.text('body passed'), findsOneWidget);
  });
}
