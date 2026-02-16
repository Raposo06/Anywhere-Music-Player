package com.anywhere.music_player

import android.app.Application
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainApplication : Application() {
    companion object {
        const val ENGINE_ID = "main_engine"
        private const val CHANNEL = "com.anywhere.music_player/platform"
    }

    override fun onCreate() {
        super.onCreate()

        // Instantiate a FlutterEngine
        val flutterEngine = FlutterEngine(this)

        // Register platform channel BEFORE executing Dart code
        // so it is available when Dart main() runs
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

        // Start executing Dart code
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        // Cache the FlutterEngine to be used by FlutterActivity
        FlutterEngineCache
            .getInstance()
            .put(ENGINE_ID, flutterEngine)
    }
}
