plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPath = System.getenv("VASTRA_KEYSTORE")

android {
    namespace = "io.github.sudharamachandranrajeev.vastra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.sudharamachandranrajeev.vastra"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingPath != null) {
            create("release") {
                storeFile = file(signingPath)
                storePassword = System.getenv("VASTRA_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("VASTRA_KEY_ALIAS")
                keyPassword = System.getenv("VASTRA_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (signingPath != null) "release" else "debug")
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

dependencies {
    // FileProvider hands a verified update package to the system installer.
    implementation("androidx.core:core:1.13.1")
}

// Public release tasks must use the persistent Vastra signing key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release", ignoreCase = true) } && signingPath == null && System.getenv("VASTRA_ALLOW_DEBUG_SIGNING") != "true") {
        throw GradleException("Set VASTRA_KEYSTORE and its signing environment values, or explicitly opt in to VASTRA_ALLOW_DEBUG_SIGNING=true for a local test APK.")
    }
}
