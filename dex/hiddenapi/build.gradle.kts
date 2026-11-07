plugins {
    alias(libs.plugins.androidLibrary)
}

android {
    namespace = "com.xayah.hiddenapi"
    compileSdkVersion("android-37.0")

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        aidl = true
    }

    // Refine 4.4 processor supports Java 11; these compile-only API stubs need no Java 17 features.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    annotationProcessor(libs.refine.annotation.processor)
    compileOnly(libs.refine.annotation)
}