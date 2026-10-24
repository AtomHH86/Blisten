/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_libs_android_audio;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Objects;
import java.io.InputStream;
import java.io.BufferedReader;
import java.util.regex.Pattern;
import java.io.InputStreamReader;
import java.util.zip.GZIPInputStream;

import android.util.Log;
import android.content.Context;
import androidx.annotation.NonNull;
import android.content.res.AssetManager;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;

import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper;


/** MediaKitLibsAndroidAudioPlugin */
public class MediaKitLibsAndroidAudioPlugin implements FlutterPlugin {
    private MethodChannel nativeTlsChannel;

    static {
        // DynamicLibrary.open on Dart side may not work on some ancient devices unless System.loadLibrary is called first.
        try {
            System.loadLibrary("mpv");
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        Log.i("media_kit", "package:media_kit_libs_android_audio attached.");
        try {
            // Save android.content.Context for access later within MediaKitAndroidHelpers e.g. loading bundled assets.
            MediaKitAndroidHelper.setApplicationContextJava(flutterPluginBinding.getApplicationContext());
            Log.i("media_kit", "Saved application context.");
        } catch (Throwable e) {
            e.printStackTrace();
        }
        final Context context = flutterPluginBinding.getApplicationContext();
        nativeTlsChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(),
                "blisten/native_tls", StandardMethodCodec.INSTANCE,
                flutterPluginBinding.getBinaryMessenger().makeBackgroundTaskQueue());
        nativeTlsChannel.setMethodCallHandler((call, result) -> {
            if (!"trustedCaFile".equals(call.method)) {
                result.notImplemented();
                return;
            }
            try {
                result.success(TrustedCaStore.write(context).getAbsolutePath());
            } catch (Exception e) {
                result.error("trusted_ca_unavailable",
                        "Unable to prepare Android trusted CA certificates.", null);
            }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (nativeTlsChannel != null) {
            nativeTlsChannel.setMethodCallHandler(null);
            nativeTlsChannel = null;
        }
        Log.i("media_kit", "package:media_kit_libs_android_audio attached.");
    }
}
