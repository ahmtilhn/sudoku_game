package com.devoviastudio.sudoku

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localizationChannel = "com.devovia.sudoku/localization"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            localizationChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getStrings") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val keys = call.argument<List<String>>("keys").orEmpty()
            val values = mutableMapOf<String, String>()
            for (key in keys) {
                val identifier = resources.getIdentifier(key, "string", packageName)
                if (identifier != 0) {
                    values[key] = resources.getString(identifier)
                }
            }
            result.success(values)
        }
    }
}
