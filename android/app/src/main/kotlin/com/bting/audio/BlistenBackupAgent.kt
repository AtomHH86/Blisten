package com.bting.audio

import android.app.backup.BackupAgentHelper
import android.app.backup.FullBackupDataOutput
import java.io.File

/** Back up settings/favorites only, after removing any legacy session value. */
class BlistenBackupAgent : BackupAgentHelper() {
    override fun onFullBackup(data: FullBackupDataOutput) {
        try {
            CredentialStorage.migrateLegacy(this)
        } catch (_: Exception) {
            // Fail closed: this backup omits preferences if migration failed.
            return
        }
        val prefs = File(applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml")
        if (prefs.exists()) fullBackupFile(prefs, data)
    }
}
