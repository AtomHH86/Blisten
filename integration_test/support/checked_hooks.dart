import 'dart:async';

import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';

/// Flutter drive reads binding.results, while package:test setup/cleanup errors
/// can occur outside binding.runTest. Preserve those failures in both channels.
/// Initialize the binding before registering hooks: package:test runs teardown
/// hooks in reverse registration order, so our result is recorded before the
/// binding's own tearDownAll completes allTestsPassed.
Future<void> guardedHook(
  String name,
  FutureOr<void> Function() body, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  try {
    // An explicit hook deadline makes timeout enter this catch and report a
    // failure. Keep it below the driver's 10-minute deadline and the framework's
    // 12-minute synthetic setUpAll/tearDownAll timeout.
    await Future<void>.sync(body).timeout(timeout);
  } catch (error, stack) {
    IntegrationTestWidgetsFlutterBinding.instance.results[name] = Failure(
      name,
      '$error\n$stack',
    );
    rethrow;
  }
}
