plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

// رقم الإصدار يزيد مع كل بناء في GitHub Actions، ويبدأ فوق أرقام التطبيق القديم
val versionCodeProp = (findProperty("VERSION_CODE") as String?)?.toInt() ?: 1
val keystoreFile: String? = System.getenv("ANDROID_KEYSTORE_FILE")

android {
    namespace = "com.majlisk.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.majlisk.app"
        minSdk = 24
        targetSdk = 36
        versionCode = versionCodeProp
        versionName = "2.0.$versionCodeProp"
        manifestPlaceholders["admobAppId"] = "ca-app-pub-4779146366215281~8891548077"
        buildConfigField("String", "API_URL", "\"https://majlisk-api.majlisk.workers.dev/api\"")
        buildConfigField("String", "ADMOB_REWARDED", "\"ca-app-pub-4779146366215281/9350713079\"")
    }

    signingConfigs {
        create("release") {
            if (keystoreFile != null) {
                storeFile = file(keystoreFile)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = "majlisk"
                keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            if (keystoreFile != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    androidResources {
        noCompress += "mp3"
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.06.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.1")
    implementation("androidx.core:core-ktx:1.16.0")

    implementation(platform("com.google.firebase:firebase-bom:33.15.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")

    implementation("androidx.credentials:credentials:1.5.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.5.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.getstream:stream-webrtc-android:1.3.10")
    implementation("com.google.android.gms:play-services-ads:24.4.0")
    implementation("com.android.billingclient:billing-ktx:7.1.1")
}
