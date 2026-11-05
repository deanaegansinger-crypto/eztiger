plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.deano.eztiger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.deano.eztiger"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // EZtiger is installed by hand (not from the Play Store). Every build must
    // be signed with the same key so a new version installs over the old one
    // and keeps the library, queue and playlists. GitHub passes that key in
    // from the repository secrets ANDROID_KEYSTORE_BASE64 and
    // ANDROID_KEYSTORE_PASSWORD (see the Android workflow); without them the
    // build falls back to a throwaway debug key.
    val keystorePath = System.getenv("EZTIGER_KEYSTORE")
    signingConfigs {
        if (keystorePath != null) {
            create("sideload") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("EZTIGER_KEYSTORE_PASSWORD")
                keyAlias = "eztiger"
                keyPassword = System.getenv("EZTIGER_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keystorePath != null) "sideload" else "debug")
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
