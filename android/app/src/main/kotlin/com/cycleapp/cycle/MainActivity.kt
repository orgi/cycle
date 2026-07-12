package com.cycleapp.cycle

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native bridges (no plugins, to stay compatible with this project's AGP 9 +
 * standalone-Kotlin build):
 *  - `cycle/incoming_gpx`: a `.gpx` the app was opened with (ACTION_VIEW) or
 *    shared with (ACTION_SEND) — read and handed to Dart on demand.
 *  - `cycle/incoming_backup`: same idea for a `.sqlite` ride-database backup
 *    (e.g. opened from a cloud-storage app after "Share backup" on another
 *    phone) — binary, so bytes are handed over rather than decoded as text.
 *  - `cycle/incoming_oruxmaps`: same idea for an OruxMaps `oruxmapstracks.db`
 *    track database (opened/shared from a file manager, no PC/adb needed) —
 *    binary, handled like the backup channel above but kept separate so a
 *    `.db` file isn't mistaken for a `.sqlite` ride backup.
 *  - `cycle/share`: hands a local file to the OS share sheet (`ACTION_SEND`)
 *    via a `FileProvider` content Uri, so "Share backup" can target OneDrive/
 *    Drive/email/Bluetooth/etc. without Cycle doing any of that app's login.
 *  - `cycle/oauth`: open a browser URL and capture the `cycle://…` OAuth
 *    redirect (Strava sign-in) so Dart can pull the authorization code.
 *  - `cycle/file_access`: check/request the "All files access" special
 *    permission (`MANAGE_EXTERNAL_STORAGE`), so a bulk OruxMaps
 *    `oruxmapstracks.db` import can read it straight from OruxMaps' own
 *    storage — Android 11+ otherwise blocks every other app, including file
 *    managers, from that path (see `OruxMapsImportService`'s doc comment).
 */
class MainActivity : FlutterActivity() {
    private val TAG = "CycleGpx"
    private val gpxChannel = "cycle/incoming_gpx"
    private val backupChannel = "cycle/incoming_backup"
    private val oruxmapsChannel = "cycle/incoming_oruxmaps"
    private val shareChannel = "cycle/share"
    private val oauthChannel = "cycle/oauth"
    private val buttonsChannel = "cycle/hardware_buttons"
    private val fileAccessChannel = "cycle/file_access"

    private var pendingName: String? = null
    private var pendingXml: String? = null
    private var pendingRedirect: String? = null
    private var pendingBackupName: String? = null
    private var pendingBackupBytes: ByteArray? = null
    private var pendingOruxName: String? = null
    private var pendingOruxBytes: ByteArray? = null

    private var buttons: MethodChannel? = null
    private var buttonsEnabled = false

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

        MethodChannel(messenger, backupChannel).setMethodCallHandler { call, result ->
            if (call.method == "consumePending") {
                val bytes = pendingBackupBytes
                if (bytes == null) {
                    result.success(null)
                } else {
                    val map = mapOf(
                        "name" to (pendingBackupName ?: "cycle_backup.sqlite"),
                        "bytes" to bytes,
                    )
                    pendingBackupName = null
                    pendingBackupBytes = null
                    result.success(map)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, oruxmapsChannel).setMethodCallHandler { call, result ->
            if (call.method == "consumePending") {
                val bytes = pendingOruxBytes
                if (bytes == null) {
                    result.success(null)
                } else {
                    val map = mapOf(
                        "name" to (pendingOruxName ?: "oruxmapstracks.db"),
                        "bytes" to bytes,
                    )
                    pendingOruxName = null
                    pendingOruxBytes = null
                    result.success(map)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, shareChannel).setMethodCallHandler { call, result ->
            if (call.method == "shareFile") {
                val path = call.arguments as? String
                if (path == null) {
                    result.error("bad_args", "path required", null)
                } else {
                    try {
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", File(path))
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, "Share backup"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        buttons = MethodChannel(messenger, buttonsChannel)
        buttons!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    buttonsEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
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

        MethodChannel(messenger, fileAccessChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAllFilesAccess" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        true // scoped storage didn't restrict Android/data before R
                    }
                    result.success(granted)
                }
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                )
                            )
                        } catch (e: Exception) {
                            // Some OEM ROMs don't resolve the per-app intent; fall back
                            // to the general "All files access" list.
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                )
                            } catch (e2: Exception) {
                                result.error("request_failed", e2.message, null)
                                return@setMethodCallHandler
                            }
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "cycle/battery").setMethodCallHandler { call, result ->
            if (call.method == "getLevel") {
                val bm = getSystemService(android.content.Context.BATTERY_SERVICE)
                    as android.os.BatteryManager
                val level = bm.getIntProperty(
                    android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                result.success(if (level in 0..100) level else null)
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

    // When hardware-button control is enabled, the volume keys toggle recording
    // (start = up, stop = down) instead of changing the volume. Mounted on a
    // handlebar, the phone's physical buttons are the natural ride control.
    //
    // We intercept in dispatchKeyEvent, NOT onKeyDown: a FlutterActivity routes
    // key events through the FlutterView first, which consumes the volume keys
    // before they ever reach Activity.onKeyDown — so onKeyDown never fires and
    // the system changes the volume. dispatchKeyEvent is the activity's first
    // look at the event, before the view hierarchy / default volume handling.
    // We consume BOTH down and up (and ignore key-repeat) so the volume neither
    // changes nor shows its UI, and a long press toggles only once.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (buttonsEnabled &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val which =
                    if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                Log.i(TAG, "volume key -> $which")
                buttons?.invokeMethod("onVolumeKey", which)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
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
        val name = displayName(uri)
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
            if (name.endsWith(".sqlite", ignoreCase = true)) {
                pendingBackupName = name
                pendingBackupBytes = bytes
                Log.i(TAG, "handleIntent read ${bytes.size} bytes backup name=$name")
            } else if (name.endsWith(".db", ignoreCase = true)) {
                pendingOruxName = name
                pendingOruxBytes = bytes
                Log.i(TAG, "handleIntent read ${bytes.size} bytes oruxmaps db name=$name")
            } else {
                pendingXml = String(bytes, Charsets.UTF_8)
                pendingName = name.replace(Regex("\\.gpx$", RegexOption.IGNORE_CASE), "")
                Log.i(TAG, "handleIntent read ${bytes.size} bytes name=$pendingName")
            }
        } catch (e: Exception) {
            Log.w(TAG, "handleIntent failed to read $uri", e)
        }
    }

    /** Raw display name (with extension) — a content Uri's real filename, or the
     * last path segment for a file:// Uri. */
    private fun displayName(uri: Uri): String {
        var name = "file"
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
        return name
    }
}
