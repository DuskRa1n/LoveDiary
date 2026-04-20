package com.example.love_diary

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_diary/platform_paths",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppDocumentsDir" -> {
                    result.success(applicationContext.filesDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_diary/sync_foreground",
        ).setMethodCallHandler { call, result ->
            val label = call.argument<String>("label") ?: "正在同步 OneDrive"
            val progress = call.argument<Double>("progress") ?: -1.0
            when (call.method) {
                "start" -> {
                    startSyncForegroundService(SyncForegroundService.ACTION_START, label, progress)
                    result.success(null)
                }
                "update" -> {
                    startSyncForegroundService(SyncForegroundService.ACTION_UPDATE, label, progress)
                    result.success(null)
                }
                "stop" -> {
                    stopSyncForegroundService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        requestHighestRefreshRate()
        requestFlutterSurfaceFrameRate()
    }

    private fun requestHighestRefreshRate() {
        val attributes = window.attributes

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }

            val bestMode = currentDisplay?.supportedModes?.maxByOrNull { it.refreshRate }
            if (bestMode != null) {
                attributes.preferredDisplayModeId = bestMode.modeId
                attributes.preferredRefreshRate = bestMode.refreshRate
            }
        } else {
            val refreshRate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display?.refreshRate
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.refreshRate
            }
            if (refreshRate != null) {
                attributes.preferredRefreshRate = refreshRate
            }
        }

        window.attributes = attributes
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun startSyncForegroundService(action: String, label: String, progress: Double) {
        val intent = Intent(this, SyncForegroundService::class.java).apply {
            this.action = action
            putExtra(SyncForegroundService.EXTRA_LABEL, label)
            putExtra(SyncForegroundService.EXTRA_PROGRESS, progress)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopSyncForegroundService() {
        val intent = Intent(this, SyncForegroundService::class.java).apply {
            action = SyncForegroundService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun requestFlutterSurfaceFrameRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }

        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            null
        } ?: return

        val targetRate = currentDisplay.supportedModes
            .maxOfOrNull { it.refreshRate }
            ?: currentDisplay.refreshRate

        val surfaceView = findSurfaceView(window.decorView) ?: return
        val surface = surfaceView.holder.surface
        if (!surface.isValid) {
            surfaceView.post { requestFlutterSurfaceFrameRate() }
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            surface.setFrameRate(
                targetRate,
                Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                Surface.CHANGE_FRAME_RATE_ALWAYS,
            )
        } else {
            @Suppress("DEPRECATION")
            surface.setFrameRate(
                targetRate,
                Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
            )
        }
    }

    private fun findSurfaceView(view: View?): SurfaceView? {
        when (view) {
            null -> return null
            is SurfaceView -> return view
            is ViewGroup -> {
                for (index in 0 until view.childCount) {
                    val child = findSurfaceView(view.getChildAt(index))
                    if (child != null) {
                        return child
                    }
                }
            }
        }
        return null
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 2308
    }
}
