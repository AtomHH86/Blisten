import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'native_audio_tls.dart';

Future<void> configurePlayerTls(Player player) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  final native = player.platform! as NativePlayer;
  await NativeAudioTls.configure(
    setProperty: native.setProperty,
    getProperty: native.getProperty,
  );
}
