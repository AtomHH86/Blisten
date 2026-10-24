import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/credential_store.dart';
import 'package:blisten/core/network/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native credential migration preserves ordinary settings and logout clears session',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await CredentialStore.instance.write(null);
      await prefs.setString(
        'bili_cookie',
        'SESSDATA=SYNTHETIC_NATIVE_MIGRATION',
      );
      await prefs.setString('abts_shelf', '[{"synthetic":true}]');
      await prefs.setDouble('synthetic_speed', 1.5);
      CookieJar.instance.clear();
      await BiliClient.instance.initLocal();
      expect(BiliClient.instance.isLoggedIn, isTrue);
      await prefs.reload();
      expect(prefs.containsKey('bili_cookie'), isFalse);
      expect(prefs.getString('abts_shelf'), '[{"synthetic":true}]');
      expect(prefs.getDouble('synthetic_speed'), 1.5);
      CookieJar.instance.clear();
      await BiliClient.instance.initLocal();
      expect(BiliClient.instance.isLoggedIn, isTrue);
      await BiliClient.instance.logout();
      expect(await CredentialStore.instance.load(), isNull);
      expect(prefs.getString('abts_shelf'), '[{"synthetic":true}]');
      await prefs.remove('abts_shelf');
      await prefs.remove('synthetic_speed');
    },
  );
}
