import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/bili_client.dart';
import 'bili_api.dart';

enum LoginStatus { loggedOut, verified, expired, unverified }

/// Only a current nav response verifies a login; cached profiles never do.
class LoginStore extends ChangeNotifier {
  LoginStore._();
  static final LoginStore instance = LoginStore._();

  LoginStatus _status = LoginStatus.loggedOut;
  String _userName = '';
  String _userFace = '';

  LoginStatus get status => _status;
  bool get isLogin => _status == LoginStatus.verified;
  String get userName => _userName;
  String get userFace => _userFace;
  BiliClient get _client => BiliClient.instance;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('bili_login_user');
    _status = _client.isLoggedIn ? LoginStatus.unverified : LoginStatus.loggedOut;
    _userName = '';
    _userFace = '';
    notifyListeners();
  }

  Future<void> refreshFromNav() async {
    final generation = _client.sessionGeneration;
    try {
      final u = await BiliApi.instance.currentUser();
      if (generation != _client.sessionGeneration) return;
      if (!u.isLogin) {
        await _expire();
        return;
      }
      _status = LoginStatus.verified;
      _userName = u.uname;
      _userFace = u.face;
      notifyListeners();
    } on BiliApiException catch (e) {
      if (generation != _client.sessionGeneration) return;
      if (e.code == -101) {
        await _expire();
      } else {
        _unverified();
      }
    } catch (_) {
      if (generation != _client.sessionGeneration) return;
      _unverified();
    }
  }

  void _unverified() {
    _status = _client.isLoggedIn ? LoginStatus.unverified : LoginStatus.loggedOut;
    _userName = '';
    _userFace = '';
    notifyListeners();
  }

  Future<void> _expire() async {
    final hadSession = _client.isLoggedIn ||
        _status == LoginStatus.verified || _status == LoginStatus.unverified;
    // logout invalidates the response generation synchronously.
    final clearing = _client.logout();
    _status = hadSession ? LoginStatus.expired : LoginStatus.loggedOut;
    _userName = '';
    _userFace = '';
    notifyListeners();
    await clearing;
  }

  Future<void> markLoggedOut() async {
    final clearing = _client.logout();
    _status = LoginStatus.loggedOut;
    _userName = '';
    _userFace = '';
    notifyListeners();
    await clearing;
  }
}
