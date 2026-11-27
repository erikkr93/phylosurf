plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ncbi_taxonomy_explorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ncbi_taxonomy_explorer"
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

tasks.configureEach {
    if (name == "assembleRelease") {
        doLast {
            val outDir = rootProject.layout.buildDirectory.dir("app/outputs/flutter-apk").get().asFile
            if (outDir.exists()) {
                outDir.listFiles { f -> f.name.startsWith("app-") && f.name.endsWith("-release.apk") }
                    ?.forEach { src ->
                        val targetName = src.name
                            .removePrefix("app-")
                            .replace("-release.apk", ".apk")
                        src.copyTo(file("${outDir.path}/phylosurf-$targetName"), overwrite = true)
                    }
                val universal = file("${outDir.path}/app-release.apk")
                if (universal.exists()) {
                    universal.copyTo(file("${outDir.path}/phylosurf.apk"), overwrite = true)
                }
            }
        }
    }
}
