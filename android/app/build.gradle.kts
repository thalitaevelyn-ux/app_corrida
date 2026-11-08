import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de assinatura da Play Store: android/key.properties (fora do git).
// Modelo em android/key.properties.example; passo a passo em docs/PUBLICAR.md.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null

android {
    namespace = "com.thalitaevelyn.fast_run"
    compileSdk = 37 // permission_handler_android exige 37+
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identificador permanente na Play Store: não troque depois de publicar.
        applicationId = "com.thalitaevelyn.fast_run"
        minSdk = 26 // exigido pelo Health Connect
        targetSdk = flutter.targetSdkVersion
        // Vêm de "version:" no pubspec.yaml (ex.: 1.0.0+1 → versionName 1.0.0, versionCode 1).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sem key.properties, assina com a chave de debug (serve para testar,
            // mas a Play Store recusa).
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
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
