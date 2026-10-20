plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.readtrans.spike"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.readtrans.spike"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // 刻意只留 Maven Central 上的套件，讓沒有 Google Maven 的環境也能編譯。
    // 產品版的 L0 翻譯改接 ML Kit（com.google.mlkit:translate），見 docs/08 §3.1。
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
