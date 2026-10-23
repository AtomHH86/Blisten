import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['BLISTEN_SCREENSHOT_DIR'] ??
        'build/desktop-tests/visual-screenshots',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      // Capture validation only; human review is recorded in the test report.
      if (bytes.length < 24 || bytes[0] != 137 || bytes[1] != 80) return false;
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: null,
  );
}
