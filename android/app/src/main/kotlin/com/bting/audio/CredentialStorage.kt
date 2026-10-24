package com.bting.audio

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException

/** Session values never enter the shared preferences backup domain. */
internal object CredentialStorage {
    private fun file(context: Context) = AtomicFile(File(context.noBackupFilesDir, "bili_session"))

    @Synchronized
    fun read(context: Context): String? {
        val file = file(context)
        return try {
            String(file.readFully(), Charsets.UTF_8)
        } catch (_: FileNotFoundException) {
            null
        }
    }

    @Synchronized
    fun write(context: Context, cookie: String?) {
        val file = file(context)
        if (cookie.isNullOrEmpty()) {
            file.delete()
            return
        }
        val stream = file.startWrite()
        try {
            stream.write(cookie.toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    /** Also called before backup, including before the first upgraded launch. */
    @Synchronized
    fun migrateLegacy(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val legacy = prefs.getString("flutter.bili_cookie", null) ?: return
        if (read(context) == null && legacy.isNotEmpty()) write(context, legacy)
        check(prefs.edit().remove("flutter.bili_cookie").commit())
    }
}
