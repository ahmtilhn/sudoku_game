package com.devoviastudio.sudoku

import android.app.Activity
import android.content.Intent
import com.google.android.gms.games.AnnotatedData
import com.google.android.gms.games.FriendsResolutionRequiredException
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayerBuffer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localizationChannel = "com.devovia.sudoku/localization"
    private val gameServicesChannel = "com.devoviastudio.sudoku/game_services"
    private val friendsConsentRequestCode = 9401
    private var pendingFriendsResult: MethodChannel.Result? = null

    private val isPlayGamesConfigured: Boolean
        get() {
            val projectId = getString(R.string.game_services_project_id).trim()
            return projectId.isNotEmpty() && projectId != "0000000000"
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureLocalizationChannel(flutterEngine)
        configureGameServicesChannel(flutterEngine)
    }

    private fun configureLocalizationChannel(flutterEngine: FlutterEngine) {
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

    private fun configureGameServicesChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            gameServicesChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isConfigured" -> result.success(isPlayGamesConfigured)
                "isAuthenticated" -> checkAuthentication(result, prompt = false)
                "authenticate" -> checkAuthentication(result, prompt = true)
                "getLocalPlayer" -> getLocalPlayer(result)
                "loadFriends" -> loadFriends(result)
                "showPlayerProfile" -> {
                    val playerId = call.argument<String>("playerId").orEmpty()
                    showPlayerProfile(playerId, result)
                }
                "showAchievements" -> showAchievements(result)
                "showLeaderboard" -> {
                    val requestedId = call.argument<String>("leaderboardId")
                    showLeaderboard(requestedId, result)
                }
                "submitScore" -> {
                    val requestedId = call.argument<String>("leaderboardId")
                    val score = call.argument<Number>("score")?.toLong()
                    submitScore(requestedId, score, result)
                }
                "unlockAchievement" -> {
                    val requestedId = call.argument<String>("achievementId")
                    unlockAchievement(requestedId, result)
                }
                "requestServerAuthCode" -> requestServerAuthCode(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureConfigured(result: MethodChannel.Result): Boolean {
        if (isPlayGamesConfigured) return true
        result.error(
            "not_configured",
            "Replace the Play Games project and OAuth placeholders first.",
            null,
        )
        return false
    }

    private fun checkAuthentication(result: MethodChannel.Result, prompt: Boolean) {
        if (!ensureConfigured(result)) return
        val client = PlayGames.getGamesSignInClient(this)
        val task = if (prompt) client.signIn() else client.isAuthenticated
        task.addOnCompleteListener { completed ->
            if (!completed.isSuccessful) {
                result.error(
                    "authentication_failed",
                    completed.exception?.localizedMessage ?: "Play Games authentication failed.",
                    null,
                )
                return@addOnCompleteListener
            }
            result.success(completed.result.isAuthenticated)
        }
    }

    private fun getLocalPlayer(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        PlayGames.getPlayersClient(this).currentPlayer
            .addOnSuccessListener { player ->
                result.success(
                    mapOf(
                        "platform" to "google_play_games",
                        "playerId" to player.playerId,
                        "displayName" to player.displayName,
                        "avatarUrl" to player.hiResImageUri?.toString(),
                    ),
                )
            }
            .addOnFailureListener { exception ->
                result.error("player_unavailable", exception.localizedMessage, null)
            }
    }

    private fun loadFriends(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        if (pendingFriendsResult != null) {
            result.error("friends_request_in_progress", "A friends request is already active.", null)
            return
        }
        performLoadFriends(result)
    }

    private fun performLoadFriends(result: MethodChannel.Result) {
        PlayGames.getPlayersClient(this)
            .loadFriends(50, false)
            .addOnSuccessListener { data: AnnotatedData<PlayerBuffer> ->
                val buffer = data.get()
                if (buffer == null) {
                    result.success(emptyList<Map<String, String?>>())
                    return@addOnSuccessListener
                }
                try {
                    val friends = mutableListOf<Map<String, String?>>()
                    for (index in 0 until buffer.count) {
                        val player = buffer[index]
                        friends.add(
                            mapOf(
                                "platform" to "google_play_games",
                                "playerId" to player.playerId,
                                "displayName" to player.displayName,
                                "avatarUrl" to player.iconImageUri?.toString(),
                            ),
                        )
                    }
                    result.success(friends)
                } finally {
                    buffer.release()
                }
            }
            .addOnFailureListener { exception ->
                if (exception is FriendsResolutionRequiredException) {
                    pendingFriendsResult = result
                    try {
                        startIntentSenderForResult(
                            exception.resolution.intentSender,
                            friendsConsentRequestCode,
                            null,
                            0,
                            0,
                            0,
                        )
                    } catch (launchError: Exception) {
                        pendingFriendsResult = null
                        result.error("friends_consent_failed", launchError.localizedMessage, null)
                    }
                    return@addOnFailureListener
                }
                result.error("friends_unavailable", exception.localizedMessage, null)
            }
    }

    private fun showPlayerProfile(playerId: String, result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        if (playerId.isBlank()) {
            result.error("invalid_player", "A Play Games player ID is required.", null)
            return
        }
        PlayGames.getPlayersClient(this).getCompareProfileIntent(playerId)
            .addOnSuccessListener { intent ->
                startActivityForResult(intent, 9402)
                result.success(true)
            }
            .addOnFailureListener { exception ->
                result.error("profile_unavailable", exception.localizedMessage, null)
            }
    }

    private fun showAchievements(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        PlayGames.getAchievementsClient(this).achievementsIntent
            .addOnSuccessListener { intent ->
                startActivityForResult(intent, 9403)
                result.success(true)
            }
            .addOnFailureListener { exception ->
                result.error("achievements_unavailable", exception.localizedMessage, null)
            }
    }

    private fun showLeaderboard(requestedId: String?, result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        val leaderboardId = requestedId
            ?.takeIf { it.isNotBlank() }
            ?: getString(R.string.leaderboard_global_rating)
        if (leaderboardId.startsWith("REPLACE_")) {
            result.error("not_configured", "Replace the leaderboard ID placeholder.", null)
            return
        }
        PlayGames.getLeaderboardsClient(this).getLeaderboardIntent(leaderboardId)
            .addOnSuccessListener { intent ->
                startActivityForResult(intent, 9404)
                result.success(true)
            }
            .addOnFailureListener { exception ->
                result.error("leaderboard_unavailable", exception.localizedMessage, null)
            }
    }

    private fun submitScore(
        requestedId: String?,
        score: Long?,
        result: MethodChannel.Result,
    ) {
        if (!ensureConfigured(result)) return
        if (score == null) {
            result.error("invalid_score", "A numeric score is required.", null)
            return
        }
        val leaderboardId = requestedId
            ?.takeIf { it.isNotBlank() }
            ?: getString(R.string.leaderboard_global_rating)
        if (leaderboardId.startsWith("REPLACE_")) {
            result.error("not_configured", "Replace the leaderboard ID placeholder.", null)
            return
        }
        PlayGames.getLeaderboardsClient(this).submitScore(leaderboardId, score)
        result.success(true)
    }

    private fun unlockAchievement(requestedId: String?, result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        val achievementId = requestedId
            ?.takeIf { it.isNotBlank() }
            ?: getString(R.string.achievement_first_win)
        if (achievementId.startsWith("REPLACE_")) {
            result.error("not_configured", "Replace the achievement ID placeholder.", null)
            return
        }
        PlayGames.getAchievementsClient(this).unlock(achievementId)
        result.success(true)
    }

    private fun requestServerAuthCode(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        val webClientId = getString(R.string.game_services_web_client_id).trim()
        if (webClientId.startsWith("REPLACE_")) {
            result.error("not_configured", "Replace the Play Games web client ID.", null)
            return
        }
        PlayGames.getGamesSignInClient(this)
            .requestServerSideAccess(webClientId, false)
            .addOnSuccessListener(result::success)
            .addOnFailureListener { exception ->
                result.error("server_auth_failed", exception.localizedMessage, null)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != friendsConsentRequestCode) return

        val result = pendingFriendsResult ?: return
        pendingFriendsResult = null
        if (resultCode == Activity.RESULT_OK) {
            performLoadFriends(result)
        } else {
            result.error("friends_consent_denied", "Play Games friends access was not granted.", null)
        }
    }
}
