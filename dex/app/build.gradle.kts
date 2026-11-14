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
require(componentVersion.matches(Regex("v[1-9][0-9]{2,3}"))) { "Invalid release version; run sync_version.ps1" }
val buildVersion = releaseInfo.getProperty("build")
require(buildVersion.matches(Regex("v[1-9][0-9]{2,3}"))) { "Invalid build version; run sync_version.ps1" }
val buildVersionCode = releaseInfo.getProperty("versionCode").toInt()

android {
    // AndroidHiddenApiBypass upstream recommends disabling dependency metadata reporting.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    namespace = "com.xayah.dex"
    compileSdkVersion("android-37.0")

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
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.2-4efc64fc-SNAPSHOT")
    testImplementation(libs.junit)
    implementation(libs.refine.runtime)
    implementation(libs.gson)

    compileOnly("com.google.errorprone:error_prone_annotations:2.52.0")
    compileOnly("androidx.annotation:annotation:1.11.0")
    compileOnly(project(":hiddenapi"))
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

// Audited stable dependency alignment; constraints do not add unused libraries.
dependencies { constraints {
 implementation("androidx.annotation:annotation:1.11.0")
 implementation("androidx.annotation:annotation-jvm:1.11.0")
 implementation("com.google.code.gson:gson:2.15.1-a961b0fe-SNAPSHOT")
 implementation("com.google.errorprone:error_prone_annotations:2.52.0")
 implementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.21")
 implementation("org.jetbrains:annotations:26.1.0")
 implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.2-4efc64fc-SNAPSHOT")
} }
