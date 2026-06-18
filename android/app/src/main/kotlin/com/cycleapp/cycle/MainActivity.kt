package com.cycleapp.cycle

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Captures a `.gpx` the app was opened with (ACTION_VIEW) or shared with
 * (ACTION_SEND), reads its contents, and hands them to Dart on demand over a
 * MethodChannel. Done natively (no plugin) to stay compatible with this
 * project's AGP 9 + standalone-Kotlin build.
 */
class MainActivity : FlutterActivity() {
    private val TAG = "CycleGpx"
    private val channelName = "cycle/incoming_gpx"
    private var pendingName: String? = null
    private var pendingXml: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "consumePending") {
                    val xml = pendingXml
                    Log.i(TAG, "consumePending -> ${if (xml == null) "null" else "${xml.length} chars"}")
                    if (xml == null) {
                        result.success(null)
                    } else {
                        val map = mapOf("name" to (pendingName ?: "Route"), "xml" to xml)
                        pendingName = null
                        pendingXml = null
                        result.success(map)
                    }
                } else {
                    result.notImplemented()
                }
            }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        Log.i(TAG, "handleIntent action=${intent.action} uri=$uri")
        uri ?: return
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
            pendingXml = String(bytes, Charsets.UTF_8)
            pendingName = displayName(uri)
            Log.i(TAG, "handleIntent read ${bytes.size} bytes name=$pendingName")
        } catch (e: Exception) {
            Log.w(TAG, "handleIntent failed to read $uri", e)
        }
    }

    private fun displayName(uri: Uri): String {
        var name = "Route"
        if (uri.scheme == "content") {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) {
                    c.getString(idx)?.let { name = it }
                }
            }
        } else {
            uri.lastPathSegment?.let { name = it }
        }
        return name.replace(Regex("\\.gpx$", RegexOption.IGNORE_CASE), "")
    }
}
