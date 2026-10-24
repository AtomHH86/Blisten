package com.bting.audio

import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val CACHE_CHANNEL_ID = "dev.pages.abts.channel.cache"
        private const val CACHE_NOTIFY_ID = 4201
    }

    private var cacheNotifyManager: NotificationManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Credentials are isolated from settings and all backup domains.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/credentials",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> {
                        CredentialStorage.migrateLegacy(this)
                        result.success(CredentialStorage.read(this))
                    }
                    "write" -> {
                        CredentialStorage.write(this, call.arguments as String?)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("credential_storage", "Credential storage unavailable", null)
            }
        }

        // 保存图片到相册
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/gallery",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "saveImage" -> {
                    val base64 = call.argument<String>("base64")
                    val name = call.argument<String>("name") ?: "image"
                    if (base64 == null) {
                        result.success(null)
                    } else {
                        result.success(saveImageToGallery(base64, name))
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 打开外部链接（浏览器）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/browser",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(openExternal(url))
                    }
                }

                else -> result.notImplemented()
            }
        }

        // 离线缓存进度通知（后台缓存时显示）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/cache_notify",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title") ?: "正在缓存"
                    val text = call.argument<String>("text") ?: ""
                    val progress = call.argument<Int>("progress") ?: -1
                    updateCacheNotification(title, text, progress)
                    result.success(true)
                }

                "cancel" -> {
                    cacheNotifyManager?.cancel(CACHE_NOTIFY_ID)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // 存储可用空间（缓存前预检，避免下到一半才失败）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                            stat.availableBytes
                        } else {
                            @Suppress("DEPRECATION")
                            stat.availableBlocks.toLong() * stat.blockSize.toLong()
                        })
                    } catch (e: Exception) {
                        result.success(-1L)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // 电池优化（后台留存）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abts/battery",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoring" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }

                "requestIgnore" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS))
                        } catch (_: Exception) {
                            // 系统无对应设置页时忽略
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    /** 用系统浏览器打开链接；没有可用浏览器时返回 false */
    private fun openExternal(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun updateCacheNotification(title: String, text: String, progress: Int) {
        try {
            val nm = cacheNotifyManager ?: run {
                val n = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                createCacheChannel(n)
                cacheNotifyManager = n
                n
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(this, CACHE_CHANNEL_ID)
            } else {
                android.app.Notification.Builder(this)
            }
            val b = builder.setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
            if (progress >= 0) {
                b.setProgress(100, progress, false)
            }
            nm.notify(CACHE_NOTIFY_ID, b.build())
        } catch (e: Exception) {
            // 没有通知权限等情况，忽略即可，不影响下载
        }
    }

    private fun createCacheChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = android.app.NotificationChannel(
                CACHE_CHANNEL_ID,
                "离线缓存",
                NotificationManager.IMPORTANCE_LOW,
            )
            ch.setShowBadge(false)
            ch.enableVibration(false)
            ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
    }

    /** 保存 PNG 到系统相册，返回保存路径；失败返回 null */
    private fun saveImageToGallery(base64: String, name: String): String? {
        return try {
            val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return null
            val fileName = if (name.endsWith(".png")) name else "$name.png"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(
                        android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                        "Pictures/B听",
                    )
                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return null
                contentResolver.openOutputStream(uri)?.use { os ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, os)
                }
                values.clear()
                values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                uri.toString()
            } else {
                @Suppress("DEPRECATION")
                val dir = java.io.File(
                    android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_PICTURES,
                    ),
                    "B听",
                )
                if (!dir.exists() && !dir.mkdirs()) return null
                val file = java.io.File(dir, fileName)
                java.io.FileOutputStream(file).use { os ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, os)
                }
                android.media.MediaScannerConnection.scanFile(
                    this,
                    arrayOf(file.absolutePath),
                    arrayOf("image/png"),
                    null,
                )
                file.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }
}