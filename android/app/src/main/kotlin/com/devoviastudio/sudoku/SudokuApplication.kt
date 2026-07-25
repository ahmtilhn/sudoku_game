package com.devoviastudio.sudoku

import android.util.Log
import com.google.android.gms.games.PlayGamesSdk
import io.flutter.app.FlutterApplication

class SudokuApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        val projectId = getString(R.string.game_services_project_id).trim()
        if (!isValidPlayGamesProjectId(projectId)) {
            Log.w(
                "SudokuApplication",
                "Play Games initialization skipped because the project ID is not configured.",
            )
            return
        }

        try {
            PlayGamesSdk.initialize(this)
        } catch (error: RuntimeException) {
            // Play Games is optional. A console/OAuth configuration mistake must
            // never prevent the offline Sudoku experience from launching.
            Log.e("SudokuApplication", "Play Games initialization failed.", error)
        }
    }

    private fun isValidPlayGamesProjectId(value: String): Boolean {
        return value.length in 10..20 && value.all(Char::isDigit) && value != "0000000000"
    }
}
