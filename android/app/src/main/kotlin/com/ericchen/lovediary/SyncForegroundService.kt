package com.ericchen.lovediary

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class SyncForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, ACTION_UPDATE -> {
                val label = intent.getStringExtra(EXTRA_LABEL) ?: DEFAULT_LABEL
                val progress = intent.getDoubleExtra(EXTRA_PROGRESS, -1.0)
                startOrUpdate(label, progress)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startOrUpdate(label: String, progress: Double) {
        ensureChannel()
        acquireWakeLock()

        val notification = buildNotification(label, progress)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(label: String, progress: Double): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pendingIntent = PendingIntent.getActivity(this, 0, openIntent, pendingFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val progressPercent = if (progress in 0.0..1.0) {
            (progress * 100).toInt()
        } else {
            null
        }
        val subtitle = if (progressPercent == null) {
            "OneDrive 正在同步 · 点击返回查看"
        } else {
            "OneDrive 同步 $progressPercent% · 点击返回查看"
        }

        builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(label)
            .setContentText(subtitle)
            .setStyle(Notification.BigTextStyle().setBigContentTitle(label).bigText(subtitle))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_PROGRESS)
        }

        if (progressPercent != null) {
            builder.setProgress(100, progressPercent, false)
            builder.setSubText("$progressPercent%")
        } else {
            builder.setProgress(0, 0, true)
        }

        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "日记同步",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "同步 OneDrive 时保持前台服务运行"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "LoveDiary:SyncWakeLock",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        val currentWakeLock = wakeLock
        if (currentWakeLock?.isHeld == true) {
            currentWakeLock.release()
        }
        wakeLock = null
    }

    companion object {
        const val ACTION_START = "com.ericchen.lovediary.sync.START"
        const val ACTION_UPDATE = "com.ericchen.lovediary.sync.UPDATE"
        const val ACTION_STOP = "com.ericchen.lovediary.sync.STOP"
        const val EXTRA_LABEL = "label"
        const val EXTRA_PROGRESS = "progress"

        private const val CHANNEL_ID = "love_diary_sync"
        private const val NOTIFICATION_ID = 2307
        private const val DEFAULT_LABEL = "正在同步 OneDrive"
        private const val WAKE_LOCK_TIMEOUT_MS = 30 * 60 * 1000L
    }
}
