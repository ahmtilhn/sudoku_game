import com.flutter.gradle.tasks.FlutterTask
import groovy.json.JsonSlurper
import java.io.FileInputStream
import java.net.URI
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Flutter and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val expectedPlayGamesProjectId = "917838292556"
val expectedPlayGamesServerClientId =
    "917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com"

fun xmlStringResource(xml: String, name: String): String {
    val pattern = Regex(
        """<string\s+name=[\"']${Regex.escape(name)}[\"'][^>]*>([^<]+)</string>""",
    )
    return pattern.find(xml)?.groupValues?.get(1)?.trim().orEmpty()
}

fun decodeDartDefines(rawValue: String): Map<String, String> {
    if (rawValue.isBlank()) return emptyMap()
    return rawValue.split(',')
        .filter { it.isNotBlank() }
        .associate { encoded ->
            val decoded = String(Base64.getDecoder().decode(encoded.trim()), Charsets.UTF_8)
            val separator = decoded.indexOf('=')
            if (separator <= 0) {
                throw GradleException("Invalid dart-define entry: $decoded")
            }
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        }
}

fun escapeAndroidXml(value: String): String = value
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\"", "&quot;")
    .replace("'", "\\'")

fun androidValuesDirectory(locale: String): String = when (locale) {
    "id" -> "values-in"
    "zh-Hans" -> "values-b+zh+Hans"
    "zh-Hant" -> "values-b+zh+Hant"
    else -> "values-$locale"
}

val generatedPushResources = layout.buildDirectory.dir("generated/pushNotificationRes")
val pushLocalizationCatalog = rootProject.file("../assets/localization/Localizable.xcstrings")

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseSigningConfigured = keystorePropertiesFile.exists()

if (releaseSigningConfigured) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    namespace = "com.devoviastudio.sudoku"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.devoviastudio.sudoku"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    sourceSets {
        // AGP 9+ rejects Provider<Directory> on the legacy SourceSet API.
        // Resolve it to a concrete File; preBuild below keeps task ordering.
        getByName("main").res.srcDir(generatedPushResources.get().asFile)
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("storeFile is missing from android/key.properties")
                val configuredStorePassword = keystoreProperties.getProperty("storePassword")
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("storePassword is missing from android/key.properties")
                val configuredKeyAlias = keystoreProperties.getProperty("keyAlias")
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("keyAlias is missing from android/key.properties")
                val configuredKeyPassword = keystoreProperties.getProperty("keyPassword")
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("keyPassword is missing from android/key.properties")

                storeFile = rootProject.file(storeFilePath)
                storePassword = configuredStorePassword
                keyAlias = configuredKeyAlias
                keyPassword = configuredKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }

            // Emergency store hotfix: the Play-distributed minified build crashes
            // before MainActivity while WorkManager creates its Room database.
            // Keep release optimization disabled until the dependency/R8 issue is
            // reproduced and verified independently on a release APK.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-games-v2:22.0.0")

    // Pin AndroidX startup/background components to current stable releases.
    // Older transitive WorkManager/Room combinations crashed during eager startup
    // in the minified Play build while creating WorkDatabase.
    implementation("androidx.work:work-runtime:2.11.2")
    implementation("androidx.startup:startup-runtime:1.2.0")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

fun assertProductionReleaseDefines(defines: Map<String, String>) {
    val appEnvironment = defines["APP_ENVIRONMENT"]?.trim().orEmpty()
    if (appEnvironment != "production") {
        throw GradleException(
            "APP_ENVIRONMENT=production is required for release builds.",
        )
    }

    val buildCommit = defines["BUILD_COMMIT"]?.trim().orEmpty()
    if (!Regex("^[0-9a-fA-F]{7,40}$").matches(buildCommit)) {
        throw GradleException(
            "BUILD_COMMIT must be a 7-40 character Git commit SHA for release builds.",
        )
    }

    val socialBackendUrl = defines["SOCIAL_BACKEND_URL"]?.trim().orEmpty()
    val socialUri = runCatching { URI(socialBackendUrl) }.getOrNull()
    val blockedBackend = listOf(
        "localhost",
        "127.0.0.1",
        "replace_with",
        "example",
        "staging",
        "test",
    ).any { socialBackendUrl.lowercase().contains(it) }
    if (socialUri == null ||
        socialUri.scheme != "https" ||
        socialUri.host.isNullOrBlank() ||
        socialUri.userInfo != null ||
        socialUri.query != null ||
        socialUri.fragment != null ||
        blockedBackend
    ) {
        throw GradleException(
            "Release builds require an explicit production SOCIAL_BACKEND_URL HTTPS endpoint.",
        )
    }
}

// Flutter supplies -Pdart-defines after project configuration. Validate the
// exact values consumed by the release FlutterTask so release builds cannot
// silently fall back to staging.
tasks.withType<FlutterTask>().configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            val effectiveDefines = decodeDartDefines(dartDefines.orEmpty())
            assertProductionReleaseDefines(effectiveDefines)
            logger.lifecycle(
                "Release FlutterTask {} uses production SOCIAL_BACKEND_URL={}",
                name,
                effectiveDefines["SOCIAL_BACKEND_URL"],
            )
        }
    }
}

val generateSudokuLauncherIcon by tasks.registering {
    val encodedIcon = layout.projectDirectory.file("launcher_icon_192.base64")
    val generatedIcon = layout.projectDirectory.file(
        "src/main/res/mipmap-xxxhdpi/ic_launcher_sudoku_duel.png",
    )

    inputs.file(encodedIcon)
    outputs.file(generatedIcon)

    doLast {
        val source = encodedIcon.asFile.readText().trim()
        if (source.isEmpty()) {
            throw GradleException("The Sudoku Duel launcher icon source is empty.")
        }
        generatedIcon.asFile.parentFile.mkdirs()
        generatedIcon.asFile.writeBytes(Base64.getDecoder().decode(source))
    }
}

val generatePushNotificationLocalizations by tasks.registering {
    inputs.file(pushLocalizationCatalog)
    outputs.dir(generatedPushResources)

    doLast {
        if (!pushLocalizationCatalog.exists()) {
            throw GradleException(
                "Missing ${pushLocalizationCatalog.path}; native push strings cannot be generated.",
            )
        }

        val outputRoot = generatedPushResources.get().asFile
        outputRoot.deleteRecursively()
        outputRoot.mkdirs()

        val catalog = JsonSlurper().parse(pushLocalizationCatalog) as? Map<*, *>
            ?: throw GradleException("Localizable.xcstrings must contain a JSON object.")
        val catalogStrings = catalog["strings"] as? Map<*, *>
            ?: throw GradleException("Localizable.xcstrings is missing strings.")
        val pushStrings = catalogStrings.entries
            .filter { it.key?.toString()?.startsWith("push_") == true }

        if (pushStrings.isEmpty()) {
            throw GradleException("Localizable.xcstrings contains no push_* strings.")
        }

        val byLocale = linkedMapOf<String, MutableMap<String, String>>()
        pushStrings.forEach { entry ->
            val key = entry.key.toString()
            val definition = entry.value as? Map<*, *> ?: return@forEach
            val localizations = definition["localizations"] as? Map<*, *> ?: return@forEach
            localizations.forEach localizationLoop@{ (localeKey, localizedValue) ->
                val locale = localeKey?.toString().orEmpty()
                if (locale.isBlank() || locale == "en") return@localizationLoop
                val localization = localizedValue as? Map<*, *> ?: return@localizationLoop
                val stringUnit = localization["stringUnit"] as? Map<*, *>
                    ?: return@localizationLoop
                val value = stringUnit["value"]?.toString() ?: return@localizationLoop
                byLocale.getOrPut(locale) { linkedMapOf() }[key] = value
            }
        }

        byLocale.forEach { (locale, values) ->
            val valuesDirectory = androidValuesDirectory(locale)
            val sourceStrings = layout.projectDirectory
                .file("src/main/res/$valuesDirectory/strings.xml")
                .asFile
                .takeIf { it.exists() }
                ?.readText()
                .orEmpty()
            val missingValues = values.filterKeys { key ->
                !Regex("""<string\s+name=[\"']${Regex.escape(key)}[\"']""")
                    .containsMatchIn(sourceStrings)
            }
            if (missingValues.isEmpty()) return@forEach

            val directory = outputRoot.resolve(valuesDirectory)
            directory.mkdirs()
            val xml = buildString {
                append("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n")
                missingValues.toSortedMap().forEach { (key, value) ->
                    append("    <string name=\"")
                    append(key)
                    append("\" formatted=\"false\">")
                    append(escapeAndroidXml(value))
                    append("</string>\n")
                }
                append("</resources>\n")
            }
            directory.resolve("push_strings.xml").writeText(xml)
        }

        logger.lifecycle(
            "Generated native Android push localizations for {} locales from Localizable.xcstrings.",
            byLocale.size,
        )
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(generateSudokuLauncherIcon)
    dependsOn(generatePushNotificationLocalizations)
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Missing android/key.properties. Release builds must use the private upload key and must never fall back to the debug key.",
            )
        }

        val expectedPackageName = "com.devoviastudio.sudoku"
        val expectedFirebaseProjectId = "focus-sweep-503417-d7"
        val expectedFirebaseProjectNumber = "31445697560"
        val expectedFirebaseAppId = "1:31445697560:android:ed951eabf51d75800b2f6d"

        val servicesXml = rootProject.file("app/src/main/res/values/services.xml")
        val servicesText = servicesXml.takeIf { it.exists() }?.readText()
            ?: throw GradleException("Missing ${servicesXml.path}; release service identifiers cannot be verified.")

        val blockedReleaseValues = mapOf(
            "Google test AdMob App ID" to "ca-app-pub-3940256099942544~",
            "Meta App ID placeholder" to "000000000000000",
            "Meta client token placeholder" to "REPLACE_WITH_META_CLIENT_TOKEN",
            "Play Games project placeholder" to "REPLACE_WITH_PLAY_GAMES_PROJECT_ID",
            "Play Games OAuth placeholder" to "REPLACE_WITH_PLAY_GAMES_WEB_CLIENT_ID",
        )
        val remainingBlockedValues = blockedReleaseValues
            .filterValues { blockedValue -> servicesText.contains(blockedValue) }
            .keys
        if (remainingBlockedValues.isNotEmpty()) {
            throw GradleException(
                "Release build still contains mandatory non-production service values in services.xml: " +
                    remainingBlockedValues.joinToString(", ") +
                    ". Configure the required AdMob and Play Games identifiers before building a release AAB.",
            )
        }

        val playGamesProjectId = xmlStringResource(servicesText, "game_services_project_id")
        if (playGamesProjectId != expectedPlayGamesProjectId) {
            throw GradleException(
                "game_services_project_id belongs to the wrong Play Games project. " +
                    "Expected $expectedPlayGamesProjectId.",
            )
        }
        val playGamesWebClientId = xmlStringResource(servicesText, "game_services_web_client_id")
        if (playGamesWebClientId != expectedPlayGamesServerClientId) {
            throw GradleException(
                "game_services_web_client_id does not match the Play Games game-server credential. " +
                    "Expected $expectedPlayGamesServerClientId.",
            )
        }

        val googleServicesFile = rootProject.file("app/google-services.json")
        if (!googleServicesFile.exists()) {
            throw GradleException("Missing ${googleServicesFile.path}.")
        }
        val googleServices = JsonSlurper().parse(googleServicesFile) as? Map<*, *>
            ?: throw GradleException("google-services.json must contain a JSON object.")
        val projectInfo = googleServices["project_info"] as? Map<*, *>
            ?: throw GradleException("google-services.json is missing project_info.")
        if (projectInfo["project_id"]?.toString() != expectedFirebaseProjectId ||
            projectInfo["project_number"]?.toString() != expectedFirebaseProjectNumber
        ) {
            throw GradleException(
                "google-services.json belongs to a different Firebase project. " +
                    "Expected $expectedFirebaseProjectId ($expectedFirebaseProjectNumber).",
            )
        }

        val clients = googleServices["client"] as? List<*>
            ?: throw GradleException("google-services.json is missing client entries.")
        val androidClient = clients
            .mapNotNull { it as? Map<*, *> }
            .firstOrNull { client ->
                val clientInfo = client["client_info"] as? Map<*, *> ?: return@firstOrNull false
                val androidInfo = clientInfo["android_client_info"] as? Map<*, *>
                    ?: return@firstOrNull false
                androidInfo["package_name"]?.toString() == expectedPackageName
            }
            ?: throw GradleException(
                "google-services.json has no Android client for $expectedPackageName.",
            )
        val clientInfo = androidClient["client_info"] as? Map<*, *>
            ?: throw GradleException("The Android Firebase client is missing client_info.")
        if (clientInfo["mobilesdk_app_id"]?.toString() != expectedFirebaseAppId) {
            throw GradleException(
                "The Android Firebase App ID does not match $expectedFirebaseAppId.",
            )
        }

        // Firebase runtime configuration intentionally belongs to project
        // focus-sweep-503417-d7, while Play Games belongs to sudoku-503420.
        // The game-server OAuth client is therefore not expected to appear in
        // google-services.json. It is configured manually in both Play Console
        // and Firebase Authentication's Play Games provider. Never commit its
        // client secret to source control.

        val dartDefines = try {
            decodeDartDefines(project.findProperty("dart-defines")?.toString().orEmpty())
        } catch (error: IllegalArgumentException) {
            throw GradleException("Unable to decode dart-defines for release validation.", error)
        }
        assertProductionReleaseDefines(dartDefines)
        val socialUri = URI(dartDefines["SOCIAL_BACKEND_URL"])

        logger.lifecycle(
            "Verified release services: Firebase={}, PlayGames={}, serverOAuth={}, backend={}",
            expectedFirebaseProjectId,
            playGamesProjectId,
            playGamesWebClientId,
            socialUri.host,
        )
    }
}
