import 'package:media_kit/media_kit.dart';

// The browser validates HTTPS with its own trust store. Native mpv properties
// are unavailable here; no TLS override or certificate bypass is installed.
Future<void> configurePlayerTls(Player player) async {}
