plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.crmapp.mobile"
    // flutter_secure_storage 11.x requires compileSdk 37+ — the Flutter
    // Gradle plugin's own default (flutter.compileSdkVersion) is still 36
    // in this Flutter SDK version, so it's overridden explicitly here.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.crmapp.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // CRM_NO_RECORDER=1 -> a debug build without the accessibility-service call recorder, which
    // Google Play Protect blocks when an APK is sideloaded (see src/norecorder/AndroidManifest.xml).
    if (System.getenv("CRM_NO_RECORDER") == "1") {
        sourceSets.getByName("debug").manifest.srcFile("src/norecorder/AndroidManifest.xml")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
