package com.example.love_diary

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
}
