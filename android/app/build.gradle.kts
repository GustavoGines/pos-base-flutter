import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Cargar credenciales de firma desde key.properties (desarrollo local) ──────
// En CI/CD, las variables de entorno ANDROID_* sobreescriben key.properties.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "ar.com.gglabs.posmobile"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ── Configuración de firma para Release ─────────────────────────────────
    signingConfigs {
        create("release") {
            // Prioridad: variable de entorno (CI/CD) → key.properties (local)
            storeFile = file(
                System.getenv("ANDROID_KEYSTORE_PATH")
                    ?: (keyProperties.getProperty("storeFile") ?: "pos_mobile_release.jks")
            )
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                ?: keyProperties.getProperty("storePassword") ?: ""
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                ?: keyProperties.getProperty("keyAlias") ?: ""
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                ?: keyProperties.getProperty("keyPassword") ?: ""
        }
    }

    defaultConfig {
        applicationId = "ar.com.gglabs.posmobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
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
