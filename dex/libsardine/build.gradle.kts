plugins {
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.jetbrainsKotlinAndroid)
    alias(libs.plugins.serialization)
}

android {
    namespace = "com.xayah.libsardine"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    api(libs.ktor.client.core)
    api(libs.ktor.client.cio)
    api(libs.ktor.client.auth)
    api(libs.ktor.client.encoding)
    api(libs.ktor.serialization.kotlinx.xml)
    api("org.slf4j:slf4j-nop:2.0.13")
}
