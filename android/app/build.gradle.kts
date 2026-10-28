import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- Release signing -------------------------------------------------------
// Configured from either of two sources, checked in this order:
//
//   1. `android/key.properties` - local builds. Gitignored.
//   2. the ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD / ANDROID_STORE_PASSWORD
//      environment variables, plus the keystore CI decodes to
//      `android/app/upload-keystore.jks`.
//
// With neither present, release builds fall back to the DEBUG key so that
// `flutter build apk --release` still produces a runnable APK for local testing.
// Such an APK is not distributable: Play rejects it, and a device that installed
// it cannot later be upgraded by a properly signed build. See .github/RELEASING.md.
//
// The fallback is never silent: the line printed below is what stops a release
// build that quietly used the debug key from looking like a signed one.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(propertyKey: String, envVar: String): String? =
    keystoreProperties.getProperty(propertyKey) ?: System.getenv(envVar)

val releaseKeystore = run {
    val declared = keystoreProperties.getProperty("storeFile")
    // `file(...)` resolves against this module, so the bare name matches the
    // path the CI workflow decodes the keystore to.
    val candidate = if (declared != null) file(declared) else file("upload-keystore.jks")
    if (candidate.exists()) candidate else null
}

val releaseSigningReady = releaseKeystore != null &&
    signingValue("keyAlias", "ANDROID_KEY_ALIAS") != null &&
    signingValue("keyPassword", "ANDROID_KEY_PASSWORD") != null &&
    signingValue("storePassword", "ANDROID_STORE_PASSWORD") != null

if (!releaseSigningReady) {
    val message =
        "no release keystore configured - signing the release build with the " +
            "DEBUG key. Runnable, but not distributable. See .github/RELEASING.md."

    // CI sets this on release tags only. A warning alone was not enough: the
    // build exited 0, and the workflow then attached the debug-signed APK to a
    // public GitHub Release. Locally, and on PRs, the variable is unset - so
    // `flutter build apk --release` keeps producing a runnable debug-signed APK
    // for testing, which is the documented and useful behaviour. What it must
    // never do is exit 0 in a job that publishes the result.
    if (System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true") {
        throw GradleException("DBS Annotator: $message")
    }
    logger.lifecycle("DBS Annotator: $message")
}

android {
    namespace = "ch.wysscenter.dbsannotator"
    // Pinned, NOT `flutter.compileSdkVersion`, which still resolves to 34 here.
    //
    // Originally forced by a dependency conflict that file_picker 12 has since
    // removed (see ../build.gradle.kts for that history). Kept deliberately: it
    // compiles the app against a current SDK instead of whatever floor the
    // bundled Flutter happens to ship, and it is the value CI has been building
    // green against. Raising compileSdk only widens which APIs the code MAY
    // call - minSdk (device eligibility) and targetSdk (opt-in to new runtime
    // behaviour) stay on the Flutter defaults, so no device behaviour changes.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ch.wysscenter.dbsannotator"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // The warning for the debug-key case is emitted above, at project
            // scope, where `logger` is unambiguously the Project logger.
            signingConfig =
                signingConfigs.getByName(if (releaseSigningReady) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
