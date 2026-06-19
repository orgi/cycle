package com.cycleapp.cycle

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native bridges (no plugins, to stay compatible with this project's AGP 9 +
 * standalone-Kotlin build):
 *  - `cycle/incoming_gpx`: a `.gpx` the app was opened with (ACTION_VIEW) or
 *    shared with (ACTION_SEND) — read and handed to Dart on demand.
 *  - `cycle/oauth`: open a browser URL and capture the `cycle://…` OAuth
 *    redirect (Strava sign-in) so Dart can pull the authorization code.
 */
class MainActivity : FlutterActivity() {
    private val TAG = "CycleGpx"
    private val gpxChannel = "cycle/incoming_gpx"
    private val oauthChannel = "cycle/oauth"

    private var pendingName: String? = null
    private var pendingXml: String? = null
    private var pendingRedirect: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, gpxChannel).setMethodCallHandler { call, result ->
            if (call.method == "consumePending") {
                val xml = pendingXml
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

        MethodChannel(messenger, oauthChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.arguments as? String
                    if (url == null) {
                        result.error("bad_args", "url required", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                }
                "consumeRedirect" -> {
                    val r = pendingRedirect
                    pendingRedirect = null
                    result.success(r)
                }
                else -> result.notImplemented()
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
        uri ?: return

        // OAuth redirect (cycle://strava-callback?code=…) — not a file.
        if (uri.scheme == "cycle") {
            pendingRedirect = uri.toString()
            Log.i(TAG, "captured oauth redirect host=${uri.host}")
            return
        }

        Log.i(TAG, "handleIntent action=${intent.action} uri=$uri")
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
