package com.devoviastudio.sudoku

import android.util.Log
import com.google.android.gms.games.PlayGamesSdk
import io.flutter.app.FlutterApplication

class SudokuApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        val appId = getString(R.string.app_id).trim()
        if (!isValidPlayGamesAppId(appId)) {
            Log.w(
                "SudokuApplication",
                "Play Games initialization skipped because app_id is not configured.",
            )
            return
        }

        try {
            PlayGamesSdk.initialize(this)
            Log.i(
                "SudokuApplication",
                "Play Games SDK initialized for package=$packageName appId=$appId.",
            )
        } catch (error: Throwable) {
            // Play Games is optional. A console/OAuth configuration mistake must
            // never prevent the offline Sudoku experience from launching.
            Log.e("SudokuApplication", "Play Games initialization failed.", error)
        }
    }

    private fun isValidPlayGamesAppId(value: String): Boolean {
        return value.length in 10..20 && value.all(Char::isDigit) && value != "0000000000"
    }
}
