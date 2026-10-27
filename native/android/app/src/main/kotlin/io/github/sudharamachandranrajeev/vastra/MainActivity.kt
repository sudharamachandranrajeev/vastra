package io.github.sudharamachandranrajeev.vastra

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands text shared or selected in other apps to Dart on "vastra/share", and
 * verified update packages to the system installer on "vastra/update".
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = sharedText(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vastra/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vastra/update").setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val file = File(call.argument<String>("path") ?: "")
            val updates = File(cacheDir, "updates").canonicalPath + File.separator
            // Only packages Vastra downloaded and verified into its own cache are installable.
            if (!file.canonicalPath.startsWith(updates) || !file.name.endsWith(".apk") || !file.isFile) {
                result.error("path", "Not a downloaded update", null)
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                result.success("permission")
                return@setMethodCallHandler
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success("started")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("shared", it) }
    }

    private fun sharedText(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            intent.getStringExtra(Intent.EXTRA_SUBJECT),
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
        ).joinToString(" ").ifBlank { null }
        Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        else -> null
    }
}
