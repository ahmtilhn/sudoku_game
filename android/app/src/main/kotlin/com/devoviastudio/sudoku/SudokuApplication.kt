package com.devoviastudio.sudoku

import com.google.android.gms.games.PlayGamesSdk
import io.flutter.app.FlutterApplication

class SudokuApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        val projectId = getString(R.string.game_services_project_id).trim()
        if (projectId.isNotEmpty() && projectId != "0000000000") {
            PlayGamesSdk.initialize(this)
        }
    }
}
