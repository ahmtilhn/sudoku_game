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

val defaultSocialBackendUrl =
    "https://sudoku-duel-social-staging.ilhanahmet246.workers.dev"
val defaultSocialBackendDefine = Base64.getEncoder().encodeToString(
    "SOCIAL_BACKEND_URL=$defaultSocialBackendUrl".toByteArray(Charsets.UTF_8),
)
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

fun withDefaultSocialBackend(rawValue: String?): String {
    val entries = rawValue
        ?.split(',')
        ?.map(String::trim)
        ?.filter(String::isNotEmpty)
        .orEmpty()
    val decoded = decodeDartDefines(entries.joinToString(","))
    if (decoded["SOCIAL_BACKEND_URL"]?.isNotBlank() == true) {
        return entries.joinToString(",")
    }
    return (entries + defaultSocialBackendDefine).joinToString(",")
}

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
    implementation("com.google.android.gms:play-services-games-v2:21.0.0")

    // Pin AndroidX startup/background components to current stable releases.
    // Older transitive WorkManager/Room combinations crashed during eager startup
    // in the minified Play build while creating WorkDatabase.
    implementation("androidx.work:work-runtime:2.11.2")
    implementation("androidx.startup:startup-runtime:1.2.0")

    // Meta Audience Network 6.21.x references these compile-time annotations.
    // Keeping the tiny annotation JAR on the release classpath prevents R8
    // from treating Nullsafe/Nullsafe.Mode as missing classes.
    implementation("com.facebook.infer.annotation:infer-annotation:0.18.0")
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

// The Flutter CLI always supplies its own -Pdart-defines list, even when the
// developer did not pass --dart-define. That command-line project property has
// precedence over android/gradle.properties. Merge the public staging endpoint
// directly into release Flutter tasks when no explicit SOCIAL_BACKEND_URL was
// supplied, so the documented plain build command remains deterministic.
tasks.withType<FlutterTask>().configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        dartDefines = withDefaultSocialBackend(dartDefines)
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

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(generateSudokuLauncherIcon)
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

        val effectiveDartDefines = try {
            withDefaultSocialBackend(
                project.findProperty("dart-defines")?.toString(),
            )
        } catch (error: IllegalArgumentException) {
            throw GradleException("Unable to decode dart-defines for release validation.", error)
        }
        val dartDefines = decodeDartDefines(effectiveDartDefines)
        val socialBackendUrl = dartDefines["SOCIAL_BACKEND_URL"]?.trim().orEmpty()
        val socialUri = runCatching { URI(socialBackendUrl) }.getOrNull()
        val blockedBackend = listOf("localhost", "127.0.0.1", "replace_with", "example")
            .any { socialBackendUrl.lowercase().contains(it) }
        if (socialUri == null ||
            socialUri.scheme != "https" ||
            socialUri.host.isNullOrBlank() ||
            socialUri.userInfo != null ||
            socialUri.query != null ||
            socialUri.fragment != null ||
            blockedBackend
        ) {
            throw GradleException(
                "SOCIAL_BACKEND_URL must be a real HTTPS endpoint. " +
                    "The normal 'flutter build appbundle --release' command injects the configured staging default when no override is supplied.",
            )
        }

        logger.lifecycle(
            "Verified release services: Firebase={}, PlayGames={}, serverOAuth={}, backend={}",
            expectedFirebaseProjectId,
            playGamesProjectId,
            playGamesWebClientId,
            socialUri.host,
        )
    }
}
