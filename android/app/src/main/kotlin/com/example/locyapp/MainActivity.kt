package com.example.locyapp

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val INTENT_CHANNEL = "com.example.locyapp/intent"
    private val LOCATION_RECEIVER_CHANNEL = "com.example.locyapp/location_receiver"

    private var sharedText: String? = null
    private var intentHandled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel xử lý intent data
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIntentData" -> {
                    // Chỉ trả về dữ liệu khi thực sự có intent mới và chưa được xử lý
                    if (sharedText != null && !intentHandled) {
                        result.success(mapOf("data" to sharedText))
                        println("Returning intent data: $sharedText")
                    } else {
                        result.success(null)
                        println("No intent data to return")
                    }
                }
                "clearIntentData" -> {
                    println("Clearing intent data")
                    intentHandled = true
                    sharedText = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Channel xử lý location receiver
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_RECEIVER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "register" -> {
                    // Đăng ký location receiver
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Reset dữ liệu cũ khi app khởi động
        if (savedInstanceState == null) {
            sharedText = null
            intentHandled = true
        }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        // Chỉ xử lý intent mới, không xử lý intent cũ khi app restart
        val isNewIntent = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0

        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain" && isNewIntent) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (text != null) {
                        sharedText = text
                        intentHandled = false
                        println("Received shared text: $text")

                        // Gọi Flutter để xử lý dữ liệu
                        if (flutterEngine != null) {
                            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, INTENT_CHANNEL)
                                .invokeMethod("onLocationReceived", mapOf("data" to text))
                        }
                    }
                }
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null) {
                    val uriString = uri.toString()
                    println("Received view intent with URI: $uriString")

                    // Xử lý các loại URI khác nhau
                    when {
                        uriString.contains("maps.google.com") ||
                        uriString.contains("goo.gl") ||
                        uriString.contains("maps.app.goo.gl") ||
                        uriString.startsWith("geo:") -> {
                            sharedText = uriString
                            intentHandled = false

                            // Gọi Flutter để xử lý dữ liệu
                            if (flutterEngine != null) {
                                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, INTENT_CHANNEL)
                                    .invokeMethod("onLocationReceived", mapOf("data" to uriString))
                            }
                        }
                    }
                }
            }
        }
    }
}
