import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blisten/core/storage/credential_store.dart';
import 'package:blisten/services/audio_focus.dart';
import 'package:blisten/services/browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('external links reject executable, local and hostless URLs', () async {
    var nativeCalls = 0;
    const channel = MethodChannel('abts/browser');
    messenger.setMockMethodCallHandler(channel, (_) async {
      nativeCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final url in [
      '',
      'javascript:alert(1)',
      'data:text/html,hello',
      'file:///private/local-file',
      'intent://open',
      '//example.com/path',
      'https:',
      'https:///path',
    ]) {
      expect(await Browser.open(url), isFalse, reason: url);
    }
    expect(nativeCalls, 0);
  });

  test('web credentials stay anonymous without reading or persisting cookies', () async {
    SharedPreferences.setMockInitialValues({'bili_cookie': 'synthetic-legacy-cookie'});
    var nativeCalls = 0;
    const channel = MethodChannel('abts/credentials');
    messenger.setMockMethodCallHandler(channel, (_) async {
      nativeCalls++;
      return 'synthetic-native-cookie';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await CredentialStore.instance.load(), isNull);
    await expectLater(
      CredentialStore.instance.write('synthetic-new-cookie'),
      throwsA(isA<UnsupportedError>()),
    );
    await CredentialStore.instance.write(null);
    await CredentialStore.instance.write('');
    expect(nativeCalls, 0);
    expect((await SharedPreferences.getInstance()).getString('bili_cookie'), 'synthetic-legacy-cookie');
  }, skip: !kIsWeb);

  test('web audio focus works without accessing native platform channels', () async {
    var nativeCalls = 0;
    const method = MethodChannel('abts/audio_focus');
    const events = MethodChannel('abts/audio_focus_events');
    for (final channel in [method, events]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        nativeCalls++;
        throw PlatformException(code: 'unexpected_native_channel');
      });
    }
    addTearDown(() {
      for (final channel in [method, events]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    final focus = AudioFocus.instance;
    focus.start();
    expect(await focus.request(speech: true), isTrue);
    expect(focus.hasFocus, isTrue);
    expect(focus.waiting, isFalse);
    await focus.abandon();
    expect(nativeCalls, 0);
  }, skip: !kIsWeb);
}
