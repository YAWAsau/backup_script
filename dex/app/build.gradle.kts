@file:Suppress("DSL_SCOPE_VIOLATION") // TODO: Remove once KTIJ-19369 is fixed
import java.util.Properties

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.refine)
    alias(libs.plugins.jetbrainsKotlinAndroid)
}

val releaseInfo = Properties().apply {
    rootProject.file("release-version.properties").inputStream().use { load(it) }
}
val componentVersion = releaseInfo.getProperty("version")
require(componentVersion.matches(Regex("v[1-9][0-9]{2}"))) { "Invalid release version; run sync_version.ps1" }
val buildVersion = releaseInfo.getProperty("build")
require(buildVersion.matches(Regex("v[1-9][0-9]{2}"))) { "Invalid build version; run sync_version.ps1" }
val buildVersionCode = releaseInfo.getProperty("versionCode").toInt()

android {
    // AndroidHiddenApiBypass upstream recommends disabling dependency metadata reporting.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    namespace = "com.xayah.dex"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.xayah.dex"
        minSdk = 26
        targetSdk = 34
        versionCode = buildVersionCode
        versionName = "$componentVersion build=$buildVersion"

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
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        buildConfig = true
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
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.1")
    testImplementation(libs.junit)
    implementation(libs.refine.runtime)
    implementation(libs.gson)

    compileOnly("androidx.annotation:annotation:1.9.1")
    compileOnly(project(":hiddenapi"))
}
