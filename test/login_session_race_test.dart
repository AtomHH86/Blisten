import 'dart:async';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/pages/login_page.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QrApi implements BiliApi {
  final pendingPoll = Completer<String>();
  int generated = 0;
  @override
  Future<({String url, String qrKey})> qrGenerate() async {
    generated++;
    return (url: 'https://example.invalid/qr/$generated', qrKey: '$generated');
  }

  @override
  Future<String> qrPoll(String qrKey) => pendingPoll.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_QrApi api) => ChangeNotifierProvider.value(
  value: LoginStore.instance,
  child: MaterialApp(home: LoginPage(api: api)),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoginStore.instance.load();
  });

  testWidgets('leaving login invalidates in-flight credential responses', (
    tester,
  ) async {
    final api = _QrApi();
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final generation = BiliClient.instance.sessionGeneration;
    await tester.pumpWidget(const SizedBox());
    expect(BiliClient.instance.sessionGeneration, greaterThan(generation));
    api.pendingPoll.complete('success');
    await tester.pump();
    expect(LoginStore.instance.isLogin, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshing QR replaces pending login and ignores old success', (
    tester,
  ) async {
    final api = _QrApi();
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final generation = BiliClient.instance.sessionGeneration;
    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    expect(BiliClient.instance.sessionGeneration, greaterThan(generation));
    expect(api.generated, 2);
    api.pendingPoll.complete('success');
    await tester.pump();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('登录成功，欢迎回来'), findsNothing);
    expect(LoginStore.instance.isLogin, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
