package com.anywhere.music_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun getCachedEngineId(): String {
        return MainApplication.ENGINE_ID
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
    }
}
