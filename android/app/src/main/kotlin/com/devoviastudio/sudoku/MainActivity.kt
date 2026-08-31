package com.devoviastudio.sudoku

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.games.AnnotatedData
import com.google.android.gms.games.FriendsResolutionRequiredException
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayerBuffer
import com.google.android.gms.tasks.Task
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val logTag = "SudokuPlayGames"
    private val playGamesServerClientId =
        "917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com"
    private val localizationChannel = "com.devovia.sudoku/localization"
    private val gameServicesChannel = "com.devoviastudio.sudoku/game_services"
    private val friendsConsentRequestCode = 9401
    private val maxAvatarBytes = 512 * 1024
    private var pendingFriendsResult: MethodChannel.Result? = null

    private val isPlayGamesConfigured: Boolean
        get() {
            val projectId = getString(R.string.game_services_project_id).trim()
            return projectId.length in 10..20 &&
                projectId.all(Char::isDigit) &&
                projectId != "0000000000"
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
                "getDiagnostics" -> result.success(playGamesDiagnostics())
                "isAuthenticated" -> checkAuthentication(result, prompt = false)
                "authenticate" -> checkAuthentication(result, prompt = true)
                "getLocalPlayer" -> getLocalPlayer(result)
                "loadFriends" -> loadFriends(result)
                "loadRecentPlayers" -> loadRecentPlayers(result)
                "showFriends" -> showFriends(result)
                "showPlayerProfile" -> {
                    val playerId = call.argument<String>("playerId").orEmpty()
                    showPlayerProfile(playerId, result)
                }
                "showAchievements" -> showAchievements(result)
                "leaderboardIds" -> result.success(leaderboardIds())
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
                "recordGameStatsEvents" -> {
                    val events = call.argument<List<*>>("events").orEmpty()
                        .mapNotNull { it as? Map<*, *> }
                    recordGameStatsEvents(events, result)
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
            playGamesDiagnostics(),
        )
        return false
    }

    private fun checkAuthentication(result: MethodChannel.Result, prompt: Boolean) {
        if (!ensureConfigured(result)) return
        val client = PlayGames.getGamesSignInClient(this)
        val task = if (prompt) client.signIn() else client.isAuthenticated
        task.addOnCompleteListener { completed ->
            if (!completed.isSuccessful) {
                if (!prompt) {
                    result.success(false)
                    return@addOnCompleteListener
                }
                val exception = completed.exception
                result.error(
                    "authentication_failed",
                    authenticationFailureMessage(exception),
                    playGamesDiagnostics(exception),
                )
                return@addOnCompleteListener
            }

            val authenticated = completed.result.isAuthenticated
            if (authenticated || !prompt) {
                result.success(authenticated)
                return@addOnCompleteListener
            }

            result.error(
                "not_authenticated",
                "Play Games completed sign-in but returned isAuthenticated=false. " +
                    diagnosticSummary(),
                playGamesDiagnostics(),
            )
        }
    }

    private fun authenticationFailureMessage(exception: Exception?): String {
        val apiException = exception as? ApiException
        val reason = exception?.localizedMessage?.takeIf { it.isNotBlank() }
            ?: "Play Games authentication failed."
        val status = apiException?.statusCode
        val statusText = status?.let(CommonStatusCodes::getStatusCodeString)
        return buildString {
            append(reason)
            if (status != null) {
                append(" statusCode=")
                append(status)
                append(" (")
                append(statusText)
                append(')')
            }
            append(" | ")
            append(diagnosticSummary())
        }
    }

    private fun diagnosticSummary(): String {
        return playGamesDiagnostics().entries.joinToString(", ") { (key, value) ->
            "$key=$value"
        }
    }

    private fun playGamesDiagnostics(exception: Exception? = null): Map<String, String> {
        val playServicesCode = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(this)
        val apiException = exception as? ApiException
        return linkedMapOf(
            "packageName" to packageName,
            "projectId" to getString(R.string.game_services_project_id).trim(),
            "certificateSha1" to signingCertificateSha1(),
            "installer" to installerPackageName(),
            "version" to installedVersion(),
            "playServicesStatus" to
                "$playServicesCode (${GoogleApiAvailability.getInstance().getErrorString(playServicesCode)})",
            "apiStatusCode" to (apiException?.statusCode?.toString() ?: "none"),
            "apiStatusName" to (
                apiException?.statusCode?.let(CommonStatusCodes::getStatusCodeString)
                    ?: "none"
                ),
        )
    }

    private fun installedVersion(): String {
        return runCatching {
            val info = packageManager.getPackageInfo(packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName ?: "unknown"} ($code)"
        }.getOrDefault("unknown")
    }

    private fun installerPackageName(): String {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName)
                    .installingPackageName
                    ?: "manual_or_unknown"
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
                    ?: "manual_or_unknown"
            }
        }.getOrDefault("unknown")
    }

    private fun signingCertificateSha1(): String {
        return runCatching {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES,
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }

            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = packageInfo.signingInfo
                    ?: return@runCatching "unavailable"
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
            val signature = signatures?.firstOrNull()
                ?: return@runCatching "unavailable"
            val digest = MessageDigest.getInstance("SHA-1")
                .digest(signature.toByteArray())
            digest.joinToString(":") { byte ->
                "%02X".format(Locale.US, byte.toInt() and 0xFF)
            }
        }.getOrDefault("unavailable")
    }

    private fun getLocalPlayer(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        PlayGames.getPlayersClient(this).currentPlayer
            .addOnSuccessListener { player ->
                val avatarUri = player.hiResImageUri ?: player.iconImageUri
                Thread {
                    val avatarBytes = avatarBytesBase64(avatarUri)
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "platform" to "google_play_games",
                                "playerId" to player.playerId,
                                "displayName" to player.displayName,
                                "avatarUrl" to avatarUri?.toString(),
                                "avatarBytesBase64" to avatarBytes,
                            ),
                        )
                    }
                }.start()
            }
            .addOnFailureListener { exception ->
                result.error(
                    "player_unavailable",
                    exception.localizedMessage,
                    playGamesDiagnostics(exception),
                )
            }
    }

    private fun avatarBytesBase64(uri: Uri?): String? {
        if (uri == null) return null
        val scheme = uri.scheme?.lowercase(Locale.US)
        return runCatching {
            val bytes = when (scheme) {
                "content", "file", "android.resource" ->
                    contentResolver.openInputStream(uri)?.use { stream ->
                        stream.readLimitedBytes(maxAvatarBytes)
                    }
                "https", "http" -> downloadAvatarBytes(uri.toString())
                else -> null
            }
            bytes?.let {
                if (bytes.isEmpty()) null else Base64.encodeToString(bytes, Base64.NO_WRAP)
            }
        }.getOrNull()
    }

    private fun downloadAvatarBytes(url: String): ByteArray? {
        val connection = URL(url).openConnection() as? HttpURLConnection ?: return null
        return try {
            connection.connectTimeout = 2500
            connection.readTimeout = 2500
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "SudokuDuel/1.0")
            if (connection.responseCode !in 200..299) return null
            connection.inputStream.use { stream ->
                stream.readLimitedBytes(maxAvatarBytes)
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun java.io.InputStream.readLimitedBytes(limit: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var total = 0
        while (true) {
            val read = read(buffer)
            if (read == -1) break
            total += read
            if (total > limit) return null
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
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
                result.success(playerBufferMap(data))
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

    private fun loadRecentPlayers(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        val client = PlayGames.getPlayersClient(this)
        val method = client.javaClass.methods.firstOrNull { method ->
            method.name == "loadRecentlyPlayedWithPlayers" && method.parameterCount == 1
        }
        if (method == null) {
            result.success(emptyList<Map<String, String?>>())
            return
        }
        val task = method.invoke(client, false) as? Task<*>
        if (task == null) {
            result.success(emptyList<Map<String, String?>>())
            return
        }
        task
            .addOnSuccessListener { data ->
                @Suppress("UNCHECKED_CAST")
                result.success(playerBufferMap(data as? AnnotatedData<PlayerBuffer>))
            }
            .addOnFailureListener { exception ->
                result.error("recent_players_unavailable", exception.localizedMessage, null)
            }
    }

    private fun showFriends(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        // Play Games Services v2 exposes consent-backed friend loading but no
        // stable native friends dashboard intent. Returning false lets Dart show
        // the in-app fallback instead of surfacing MissingPluginException.
        result.success(false)
    }

    private fun playerBufferMap(data: AnnotatedData<PlayerBuffer>?): List<Map<String, String?>> {
        val buffer = data?.get() ?: return emptyList()
        return try {
            val players = mutableListOf<Map<String, String?>>()
            for (index in 0 until buffer.count) {
                val player = buffer[index]
                players.add(
                    mapOf(
                        "platform" to "google_play_games",
                        "playerId" to player.playerId,
                        "displayName" to player.displayName,
                        "avatarUrl" to player.iconImageUri?.toString(),
                    ),
                )
            }
            players
        } finally {
            buffer.release()
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

    private fun leaderboardIds(): Map<String, String> = mapOf(
        "global" to getString(R.string.leaderboard_global_rating),
        "beginner" to getString(R.string.leaderboard_beginner_rating),
        "easy" to getString(R.string.leaderboard_easy_rating),
        "medium" to getString(R.string.leaderboard_medium_rating),
        "hard" to getString(R.string.leaderboard_hard_rating),
        "expert" to getString(R.string.leaderboard_expert_rating),
    )

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
        PlayGames.getAchievementsClient(this)
            .unlockImmediate(achievementId)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { exception ->
                result.error(
                    "achievement_submit_failed",
                    exception.localizedMessage ?: "Google Play achievement unlock failed.",
                    playGamesDiagnostics(exception),
                )
            }
    }

    private fun recordGameStatsEvents(
        events: List<Map<*, *>>,
        result: MethodChannel.Result,
    ) {
        if (!ensureConfigured(result)) return
        if (events.isEmpty()) {
            result.error("invalid_game_stats", "At least one Game Stats event is required.", null)
            return
        }

        try {
            val client = obtainGameStatsClient()
            val builtEvents = events.map(::buildPlayerGameEvent)
            val recordMethod = client.javaClass.methods.firstOrNull { method ->
                method.name == "recordEvent" &&
                    method.parameterCount == 1 &&
                    builtEvents.firstOrNull()?.let { event ->
                        method.parameterTypes[0].isAssignableFrom(event.javaClass)
                    } == true
            } ?: throw IllegalStateException("Game Stats recordEvent API is unavailable.")

            for (event in builtEvents) {
                recordMethod.invoke(client, event)
            }

            val uploadMethod = client.javaClass.methods.firstOrNull { method ->
                method.name == "requestEventsUpload" && method.parameterCount == 0
            } ?: throw IllegalStateException("Game Stats upload API is unavailable.")
            val uploadResult = uploadMethod.invoke(client)
            if (uploadResult is Task<*>) {
                uploadResult
                    .addOnSuccessListener { result.success(true) }
                    .addOnFailureListener { exception ->
                        result.error(
                            "game_stats_upload_failed",
                            exception.localizedMessage ?: "Game Stats upload failed.",
                            null,
                        )
                    }
            } else {
                result.success(true)
            }
        } catch (error: Throwable) {
            result.error(
                "game_stats_sdk_unavailable",
                error.cause?.localizedMessage ?: error.localizedMessage
                    ?: "Google Play Game Stats SDK is unavailable.",
                null,
            )
        }
    }

    private fun obtainGameStatsClient(): Any {
        val getter = PlayGames::class.java.methods.firstOrNull { method ->
            method.name == "getGameStatsClient" && method.parameterCount == 1
        } ?: throw IllegalStateException("PlayGames.getGameStatsClient is unavailable.")
        return getter.invoke(null, this)
            ?: throw IllegalStateException("Unable to create the Game Stats client.")
    }

    private fun buildPlayerGameEvent(event: Map<*, *>): Any {
        val eventName = event["eventName"]?.toString()?.trim().orEmpty()
        if (eventName.isEmpty()) {
            throw IllegalArgumentException("A Game Stats event name is required.")
        }
        val builderClass = playerGameEventBuilderClass()
        val constructor = builderClass.constructors.firstOrNull { candidate ->
            candidate.parameterCount == 1 &&
                candidate.parameterTypes[0].isAssignableFrom(String::class.java)
        } ?: throw IllegalStateException("PlayerGameEvent.Builder(String) is unavailable.")
        val builder = constructor.newInstance(eventName)
        val properties = event["properties"] as? Map<*, *> ?: emptyMap<Any, Any>()
        for ((rawName, rawDefinition) in properties) {
            val propertyName = rawName?.toString()?.trim().orEmpty()
            val definition = rawDefinition as? Map<*, *>
                ?: throw IllegalArgumentException("Invalid Game Stats property definition.")
            val type = definition["type"]?.toString()?.lowercase().orEmpty()
            val value = definition["value"]
                ?: throw IllegalArgumentException("Game Stats property value is required.")
            addPlayerGameEventProperty(builder, propertyName, type, value)
        }
        val buildMethod = builder.javaClass.methods.firstOrNull { method ->
            method.name == "build" && method.parameterCount == 0
        } ?: throw IllegalStateException("PlayerGameEvent.Builder.build is unavailable.")
        return buildMethod.invoke(builder)
            ?: throw IllegalStateException("Unable to build a PlayerGameEvent.")
    }

    private fun playerGameEventBuilderClass(): Class<*> {
        val candidates = listOf(
            "com.google.android.gms.games.playergameevent.PlayerGameEvent\$Builder",
            "com.google.android.gms.games.PlayerGameEvent\$Builder",
            "com.google.android.gms.games.gamestats.PlayerGameEvent\$Builder",
            "com.google.android.gms.games.gamesstats.PlayerGameEvent\$Builder",
            "com.google.android.gms.games.stats.PlayerGameEvent\$Builder",
        )
        for (name in candidates) {
            try {
                return Class.forName(name)
            } catch (_: ClassNotFoundException) {
            }
        }
        throw ClassNotFoundException("PlayerGameEvent.Builder was not found.")
    }

    private fun addPlayerGameEventProperty(
        builder: Any,
        propertyName: String,
        type: String,
        rawValue: Any,
    ) {
        if (propertyName.isBlank()) {
            throw IllegalArgumentException("A Game Stats property name is required.")
        }
        val methods = builder.javaClass.methods.filter { method ->
            method.name == "addProperty" &&
                method.parameterCount == 2 &&
                method.parameterTypes[0].isAssignableFrom(String::class.java)
        }
        val candidates: List<Pair<Class<*>, Any>> = when (type) {
            "string" -> listOf(String::class.java to rawValue.toString())
            "bool", "boolean" -> {
                val value = rawValue as? Boolean
                    ?: rawValue.toString().toBooleanStrictOrNull()
                    ?: throw IllegalArgumentException("Invalid Boolean Game Stats value.")
                listOf(Boolean::class.javaPrimitiveType!! to value, Boolean::class.java to value)
            }
            "int64", "int", "long" -> {
                val value = (rawValue as? Number)?.toLong()
                    ?: rawValue.toString().toLongOrNull()
                    ?: throw IllegalArgumentException("Invalid integer Game Stats value.")
                buildList {
                    add(Long::class.javaPrimitiveType!! to value)
                    add(Long::class.java to value)
                    if (value in Int.MIN_VALUE..Int.MAX_VALUE) {
                        add(Int::class.javaPrimitiveType!! to value.toInt())
                        add(Int::class.java to value.toInt())
                    }
                }
            }
            "double" -> {
                val value = (rawValue as? Number)?.toDouble()
                    ?: rawValue.toString().toDoubleOrNull()
                    ?: throw IllegalArgumentException("Invalid double Game Stats value.")
                listOf(
                    Double::class.javaPrimitiveType!! to value,
                    Double::class.java to value,
                    Float::class.javaPrimitiveType!! to value.toFloat(),
                    Float::class.java to value.toFloat(),
                )
            }
            else -> throw IllegalArgumentException("Unsupported Game Stats property type: $type")
        }

        for ((parameterType, value) in candidates) {
            val method = methods.firstOrNull { candidate ->
                candidate.parameterTypes[1] == parameterType
            }
            if (method != null) {
                method.invoke(builder, propertyName, value)
                return
            }
        }
        throw IllegalStateException("No compatible addProperty overload for $type.")
    }

    private fun requestServerAuthCode(result: MethodChannel.Result) {
        if (!ensureConfigured(result)) return
        val webClientId = playGamesServerClientId
        if (webClientId.startsWith("REPLACE_")) {
            result.error("not_configured", "Replace the Play Games web client ID.", null)
            return
        }
        Log.i(logTag, "Requesting Play Games server auth code with clientId=$webClientId")
        PlayGames.getGamesSignInClient(this)
            .requestServerSideAccess(webClientId, false)
            .addOnSuccessListener { authCode ->
                Log.i(logTag, "Play Games server auth code received.")
                result.success(authCode)
            }
            .addOnFailureListener { exception ->
                Log.e(logTag, "Play Games server auth code failed.", exception)
                result.error(
                    "server_auth_failed",
                    exception.localizedMessage,
                    playGamesDiagnostics(exception),
                )
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
