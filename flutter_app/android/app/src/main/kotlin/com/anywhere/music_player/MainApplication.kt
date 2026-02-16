package com.anywhere.music_player

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class MainApplication : Application() {
    companion object {
        const val ENGINE_ID = "main_engine"
    }

    override fun onCreate() {
        super.onCreate()

        // Instantiate a FlutterEngine
        val flutterEngine = FlutterEngine(this)

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
