package com.deano.eztiger

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eztiger/storage").setMethodCallHandler { call, result ->
            if (call.method == "volumes") {
                try {
                    result.success(storageVolumes())
                } catch (e: Exception) {
                    result.error("volumes", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /// Every storage place that is mounted now: internal storage, SD cards and
    /// USB sticks. Android 11 and later won't let apps list /storage, so the
    /// SD card (/storage/XXXX-XXXX) can only be found by asking Android.
    private fun storageVolumes(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val sm = getSystemService(Context.STORAGE_SERVICE) as StorageManager
            for (v in sm.storageVolumes) {
                val dir = v.directory ?: continue // not mounted
                out.add(mapOf("path" to dir.absolutePath, "label" to v.getDescription(this), "removable" to v.isRemovable))
            }
        }
        if (out.isEmpty()) {
            // Older Android: each volume has an app folder at <volume>/Android/data/<app>.
            for (f in getExternalFilesDirs(null)) {
                if (f == null) continue
                val path = f.absolutePath.substringBefore("/Android/data/")
                val removable = Environment.isExternalStorageRemovable(f)
                out.add(mapOf("path" to path, "label" to (if (removable) "SD card" else "Internal storage"), "removable" to removable))
            }
        }
        return out
    }
}
