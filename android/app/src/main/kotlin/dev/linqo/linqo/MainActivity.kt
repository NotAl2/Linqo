package dev.linqo.linqo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Html
import android.widget.Toast
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object { private val io = Executors.newSingleThreadExecutor() }
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val prefs by lazy { getSharedPreferences("share_inbox", MODE_PRIVATE) }
    private var backupResult: MethodChannel.Result? = null
    private var backupSource: File? = null
    private var notifications: ExtractionNotifications? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        notifications = ExtractionNotifications(this, MethodChannel(engine.dartExecutor.binaryMessenger, "dev.linqo/notifications"))
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.linqo/backup").setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
            } else if (backupResult != null) {
                result.error("backup_busy", "A backup destination is already open.", null)
            } else {
                try {
                    val source = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                    val root = File(cacheDir, "library-backups").canonicalFile
                    require(source.path.startsWith(root.path + File.separator) && source.isFile)
                    backupSource = source
                    backupResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "Linqo-backup.zip")
                    }, 6201)
                } catch (_: Exception) {
                    backupSource = null
                    backupResult = null
                    result.error("backup_destination", "Could not open a backup destination. Please try again.", null)
                }
            }
        }
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.linqo/share")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method != "peek" && call.method != "ack") {
                result.notImplemented()
            } else io.execute {
                try {
                    val queue = JSONArray(prefs.getString("pending", "[]"))
                    if (call.method == "peek") {
                        val first = queue.optJSONObject(0)
                        val value = first?.let { mapOf("id" to it.getString("id"),
                            "text" to it.getString("text"), "subject" to it.getString("subject"),
                            "image" to it.optString("image", "")) }
                        main.post { result.success(value) }
                    } else {
                        val id = call.argument<String>("id")
                        val remaining = JSONArray()
                        for (i in 0 until queue.length()) {
                            val entry = queue.getJSONObject(i)
                            if (entry.getString("id") != id) remaining.put(entry)
                        }
                        check(prefs.edit().putString("pending", remaining.toString()).commit())
                        main.post { result.success(null) }
                    }
                } catch (_: Exception) {
                    main.post { result.error("share_storage", "Could not read the shared link. Please share it again.", null) }
                }
            }
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        notifications?.receive(intent)
        if (state == null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) receive(intent)
    }

    override fun onNewIntent(value: Intent) {
        super.onNewIntent(value)
        setIntent(value)
        notifications?.receive(value)
        receive(value)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        notifications?.permissionFinished(requestCode)
    }

    override fun onDestroy() {
        notifications?.dispose()
        super.onDestroy()
    }

    @Deprecated("Android activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 6201) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = backupResult ?: return
        val source = backupSource
        val destination = data?.data
        if (resultCode != RESULT_OK || destination == null || source == null) {
            backupResult = null
            backupSource = null
            result.success(null)
            return
        }
        io.execute {
            try {
                contentResolver.openOutputStream(destination, "wt").use { output ->
                    requireNotNull(output)
                    source.inputStream().use { input -> input.copyTo(output) }
                }
                main.post {
                    backupResult = null
                    backupSource = null
                    result.success(destination.toString())
                }
            } catch (_: Exception) {
                // Remove the incomplete destination when the provider permits it.
                try { android.provider.DocumentsContract.deleteDocument(contentResolver, destination) } catch (_: Exception) {}
                main.post {
                    backupResult = null
                    backupSource = null
                    result.error("backup_write", "Could not write the backup. Choose another destination and retry.", null)
                }
            }
        }
    }

    private fun receive(value: Intent) {
        if (value.action != Intent.ACTION_SEND || value.type !in setOf("text/plain", "text/html", "text/uri-list")) return
        io.execute {
            try {
                // Never open arbitrary provider streams just to receive a link.
                val html = value.getStringExtra(Intent.EXTRA_HTML_TEXT)
                val raw = value.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    ?: html?.takeIf { it.length <= 30000 }?.let { Html.fromHtml(it, Html.FROM_HTML_MODE_LEGACY).toString() }
                    ?: value.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.let {
                        it.text?.toString() ?: it.uri?.takeIf { uri -> uri.scheme in setOf("http", "https") }?.toString()
                    }
                    ?: ""
                require(raw.isNotBlank() && raw.length <= 30000)
                val subject = (value.getStringExtra(Intent.EXTRA_SUBJECT)
                    ?: value.getStringExtra(Intent.EXTRA_TITLE) ?: "").take(180)
                val queue = JSONArray(prefs.getString("pending", "[]"))
                require(queue.length() < 32)
                val image = receiveImage(value)
                queue.put(JSONObject().put("id", UUID.randomUUID().toString())
                    .put("text", raw).put("subject", subject).put("image", image))
                check(prefs.edit().putString("pending", queue.toString()).commit())
                main.post { channel?.invokeMethod("shareAvailable", null) }
            } catch (_: Exception) {
                main.post { Toast.makeText(this, "Could not receive this share. Try sharing a link or shorter text.", Toast.LENGTH_LONG).show() }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun receiveImage(value: Intent): String {
        // Only an explicitly granted image accompanying a text/link share.
        // Image-only and video streams are outside this receiver's filters.
        if (value.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) return ""
        return try {
            val uri = value.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return ""
            if (uri.scheme != "content" || contentResolver.getType(uri) !in setOf("image/jpeg", "image/png", "image/webp")) return ""
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > 700 * 1024) return ""
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: return ""
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outMimeType !in setOf("image/jpeg", "image/png", "image/webp")) return ""
            if (bounds.outWidth !in 1..8192 || bounds.outHeight !in 1..8192 || bounds.outWidth.toLong() * bounds.outHeight > 16000000) return ""
            val name = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } + ".img"
            val root = File(cacheDir, "link-previews").apply { mkdirs() }
            File(root, name).writeBytes(bytes)
            var total = 0L
            root.listFiles()?.filter { it.name.matches(Regex("[a-f0-9]{64}\\.img")) }
                ?.sortedByDescending { it.lastModified() }?.forEachIndexed { index, file ->
                    total += file.length()
                    if (index >= 80 || total > 16 * 1024 * 1024) file.delete()
                }
            name
        } catch (_: Exception) { "" }
    }

    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(engine)
    }
}
