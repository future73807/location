package com.vivo.deviceFind

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.vivo.deviceFind/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "flushCookies" -> {
                    try {
                        CookieManager.getInstance().flush()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FLUSH_ERROR", e.message, null)
                    }
                }
                "ensureAcceptCookies" -> {
                    try {
                        CookieManager.getInstance().setAcceptCookie(true)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACCEPT_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
