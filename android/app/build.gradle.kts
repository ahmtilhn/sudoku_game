import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Flutter and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
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

        val servicesXml = rootProject.file("app/src/main/res/values/services.xml")
        val servicesText = servicesXml.takeIf { it.exists() }?.readText()
            ?: throw GradleException("Missing ${servicesXml.path}; release service identifiers cannot be verified.")

        // Only block identifiers that are mandatory for every release build.
        // Meta App Events is intentionally disabled, and Play Games achievements
        // may remain unconfigured while leaderboard/Game Stats internal testing is
        // performed. Their runtime methods already reject placeholders safely.
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
    }
}
