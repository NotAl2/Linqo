package dev.linqo.linqo

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/** Opt-in local notifications only. Never includes saved titles/text/URLs. */
class ExtractionNotifications(private val activity: Activity, private val channel: MethodChannel) {
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val prefs = activity.getSharedPreferences("extraction_notifications", Activity.MODE_PRIVATE)
    private var permissionResult: MethodChannel.Result? = null
    companion object {
        const val PERMISSION_REQUEST = 6502
        private const val CHANNEL = "linqo_extraction_v1"
        private const val NOTIFICATION_ID = 4100
    }
    init {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Extraction results", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "On-device extraction completion and errors"
        })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf("available" to true, "enabled" to prefs.getBoolean("enabled", false), "allowed" to allowed(), "hasNotification" to manager.activeNotifications.any { it.id == NOTIFICATION_ID }))
                "enable" -> {
                    if (call.argument<Boolean>("enabled") != true) {
                        prefs.edit().putBoolean("enabled", false).apply()
                        manager.cancel(NOTIFICATION_ID)
                        result.success(false)
                    } else if (permissionResult != null) {
                        result.error("permission_busy", "A permission request is already open.", null)
                    } else if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
                    } else {
                        val granted = allowed()
                        prefs.edit().putBoolean("enabled", granted).apply()
                        result.success(granted)
                    }
                }
                "settings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                    result.success(null)
                }
                "show" -> {
                    try {
                        if (prefs.getBoolean("enabled", false) && allowed()) {
                            show(call.argument<Number>("saveId")?.toInt(), call.argument<Boolean>("failed") == true, call.argument<Boolean>("partial") == true, call.argument<Boolean>("test") == true)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (_: SecurityException) { result.success(false) }
                }
                "takeOpenSave" -> {
                    val id = prefs.getInt("open_save", -1)
                    prefs.edit().remove("open_save").apply()
                    result.success(if (id > 0) id else null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun allowed(): Boolean = manager.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE

    fun permissionFinished(request: Int) {
        if (request != PERMISSION_REQUEST) return
        val granted = allowed()
        prefs.edit().putBoolean("enabled", granted).apply()
        permissionResult?.success(granted)
        permissionResult = null
    }
    fun receive(intent: Intent) {
        val id = intent.getIntExtra("linqo_save_id", -1)
        if (id > 0) {
            prefs.edit().putInt("open_save", id).apply()
            intent.removeExtra("linqo_save_id")
            channel.invokeMethod("openSaveAvailable", null)
        }
    }
    private fun show(id: Int?, failed: Boolean, partial: Boolean, test: Boolean) {
        val intent = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (id != null) putExtra("linqo_save_id", id)
        }
        val tap = PendingIntent.getActivity(activity, NOTIFICATION_ID, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val title = when { test -> "Linqo notifications are ready"; failed -> "Extraction needs attention"; partial -> "Extraction finished with a few gaps"; else -> "Your useful details are ready" }
        val text = when { test -> "Local notifications work without a server."; failed -> "Your save is safe. Open Linqo to retry."; partial -> "Some content could not be processed. Tap to review."; else -> "Tap to view your extracted details." }
        manager.notify(NOTIFICATION_ID, Notification.Builder(activity, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification_bookmark)
            .setColor(0xff7435c9.toInt()).setContentTitle(title).setContentText(text)
            .setContentIntent(tap).setAutoCancel(true).setOnlyAlertOnce(false)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(Notification.Builder(activity, CHANNEL).setSmallIcon(R.drawable.ic_notification_bookmark).setContentTitle("Linqo").setContentText("Extraction update").build())
            .build())
    }
    fun dispose() { permissionResult?.success(false); permissionResult = null }
}
