import 'package:blisten/player/native_audio_tls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('blisten/native_tls');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, String> properties;
  late List<String> calls;

  Future<String> get(String name) async => properties[name] ?? '';
  Future<void> set(String name, String value) async {
    calls.add('$name=$value');
    properties[name] = value;
  }

  setUp(() {
    properties = {'tls-verify': 'no', 'tls-ca-file': ''};
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'trustedCaFile');
      expect(properties['tls-verify'], 'yes');
      calls.add('trustedCaFile');
      return '/private/ca.pem';
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('enables verification before loading system trust and checks properties', () async {
    await NativeAudioTls.configure(setProperty: set, getProperty: get);
    expect(calls, ['tls-verify=yes', 'trustedCaFile', 'tls-ca-file=/private/ca.pem']);
    expect(properties['tls-verify'], 'yes');
    expect(properties['tls-ca-file'], '/private/ca.pem');
  });

  test('preserves an explicitly configured verifying player', () async {
    properties = {'tls-verify': 'yes', 'tls-ca-file': '/test-only/ca.pem'};
    await NativeAudioTls.configure(setProperty: set, getProperty: get);
    expect(calls, isEmpty);
  });

  test('verification without a CA still obtains system trust', () async {
    properties['tls-verify'] = 'yes';
    await NativeAudioTls.configure(setProperty: set, getProperty: get);
    expect(calls, contains('trustedCaFile'));
    expect(properties['tls-ca-file'], '/private/ca.pem');
  });

  test('CA export failure aborts setup without disabling verification', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'trusted_ca_unavailable');
    });
    await expectLater(
      NativeAudioTls.configure(setProperty: set, getProperty: get),
      throwsA(isA<PlatformException>()),
    );
    expect(properties['tls-verify'], 'yes');
    expect(properties['tls-ca-file'], isEmpty);
  });

  test('empty CA response aborts setup', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => '');
    await expectLater(
      NativeAudioTls.configure(setProperty: set, getProperty: get),
      throwsStateError,
    );
    expect(properties['tls-verify'], 'yes');
  });

  test('silently ignored verification setting aborts before requesting trust', () async {
    await expectLater(
      NativeAudioTls.configure(setProperty: (_, _) async {}, getProperty: get),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });

  test('silently ignored CA setting aborts setup', () async {
    Future<void> ignoredCa(String name, String value) async {
      if (name == 'tls-verify') await set(name, value);
    }
    await expectLater(
      NativeAudioTls.configure(setProperty: ignoredCa, getProperty: get),
      throwsStateError,
    );
    expect(properties['tls-verify'], 'yes');
  });
}
