@file:Suppress("DSL_SCOPE_VIOLATION") // TODO: Remove once KTIJ-19369 is fixed
plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.refine)
}

android {
    namespace = "com.xayah.dex"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.xayah.dex"
        minSdk = 26
        targetSdk = 34
        versionCode = 2438
        versionName = "2.4.38-notify-no-actions-zero-ui-buildfix"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        multiDexEnabled = false
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        buildConfig = false
    }

    packaging {
        resources {
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

configurations.configureEach {
    exclude(group = "androidx.appcompat")
    exclude(group = "androidx.activity")
    exclude(group = "androidx.fragment")
    exclude(group = "androidx.lifecycle")
    exclude(group = "androidx.emoji2")
    exclude(group = "androidx.vectordrawable")
    exclude(group = "androidx.loader")
    exclude(group = "androidx.drawerlayout")
    exclude(group = "androidx.customview")
    exclude(group = "androidx.cursoradapter")
    exclude(group = "org.apache.httpcomponents.client5")
    exclude(group = "org.apache.httpcomponents.core5")
    exclude(group = "org.slf4j")
}

dependencies {
    testImplementation(libs.junit)
    implementation(libs.refine.runtime)
    implementation(libs.gson)

    compileOnly("androidx.annotation:annotation:1.9.1")
    compileOnly(project(":hiddenapi"))
}