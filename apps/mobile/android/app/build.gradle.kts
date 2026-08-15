plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI exports signing inputs through GITHUB_ENV; retain -P support for local release builds.
fun releaseInput(name: String) =
    providers.gradleProperty(name).orElse(providers.environmentVariable(name))

val releaseStoreFile = releaseInput("AETHERTUNE_RELEASE_STORE_FILE")
val releaseStorePassword = releaseInput("AETHERTUNE_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = releaseInput("AETHERTUNE_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseInput("AETHERTUNE_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it.isPresent }

android {
    namespace = "dev.aethertune.aethertune"
    // flutter_secure_storage 11 requires Android API 37 at compile time.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseSigning) {
            create("aethertuneRelease") {
                storeFile = project.file(releaseStoreFile.get())
                storePassword = releaseStorePassword.get()
                keyAlias = releaseKeyAlias.get()
                keyPassword = releaseKeyPassword.get()
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this identifier stable so future releases upgrade the same app.
        applicationId = "dev.aethertune.aethertune"
        // Audio and secure-storage plugins require API 24.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("aethertuneRelease")
            }
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
