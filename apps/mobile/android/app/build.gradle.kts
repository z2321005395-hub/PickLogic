plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val picklogicUserTest =
    providers.gradleProperty("picklogicUserTest").orNull.equals("true", ignoreCase = true)

android {
    namespace = "io.picklogic.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId =
            if (picklogicUserTest) {
                "io.picklogic.mobile.usertest"
            } else {
                "io.picklogic.mobile"
            }
        manifestPlaceholders["picklogicAppLabel"] =
            if (picklogicUserTest) "PickLogic User Test" else "PickLogic"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing is intentionally not configured in source control.
    // Debug APKs are installable for device validation; final signing is a maintainer gate.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
