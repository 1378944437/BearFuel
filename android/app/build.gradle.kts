import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val signingKeyAlias = keystoreProperties.getProperty("keyAlias")
    ?: System.getenv("BEARFUEL_KEY_ALIAS")
val signingKeyPassword = keystoreProperties.getProperty("keyPassword")
    ?: System.getenv("BEARFUEL_KEY_PASSWORD")
val signingStoreFile = keystoreProperties.getProperty("storeFile")
    ?: System.getenv("BEARFUEL_KEYSTORE_PATH")
val signingStorePassword = keystoreProperties.getProperty("storePassword")
    ?: System.getenv("BEARFUEL_STORE_PASSWORD")

// Keep local builds on arm64 by default; the release workflow overrides this
// with all supported Android ABIs.
val configuredAbis = project.findProperty("bearfuel.targetAbis")?.toString()
val splitPerAbi = project.findProperty("split-per-abi") == "true"
val targetAbis = configuredAbis
    ?.split(',')
    ?.map(String::trim)
    ?.filter { it.isNotEmpty() }
    ?.ifEmpty { listOf("arm64-v8a") }
    ?: listOf("arm64-v8a")

android {
    namespace = "com.bearfuel.app"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bearfuel.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["applicationName"] = "android.app.Application"

        if (!splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }

    lint {
        checkReleaseBuilds = true
        abortOnError = true
    }

    signingConfigs {
        create("release") {
            keyAlias = signingKeyAlias
            keyPassword = signingKeyPassword
            storeFile = signingStoreFile?.let { file(it) }
            storePassword = signingStorePassword
        }
    }

    buildTypes {
        release {
            if (!signingStoreFile.isNullOrBlank() &&
                !signingStorePassword.isNullOrBlank() &&
                !signingKeyAlias.isNullOrBlank() &&
                !signingKeyPassword.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
