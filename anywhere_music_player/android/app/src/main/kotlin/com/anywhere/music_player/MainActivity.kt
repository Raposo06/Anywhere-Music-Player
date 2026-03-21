package com.anywhere.music_player

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.anywhere.music_player/platform"

    // Use the shared FlutterEngine from audio_service so the plugin
    // and the Activity operate on the same engine instance.
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAndroidTV" -> {
                    val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val isTV = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    result.success(isTV)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
