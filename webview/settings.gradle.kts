pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { maven { url = uri("third_party/maven"); content { includeGroup("top.yukonga.miuix.kmp"); includeGroup("io.github.kyant0"); includeGroup("com.materialkolor"); includeGroup("com.github.topjohnwu.libsu") } }; google(); mavenCentral(); maven("https://jitpack.io") { content { includeGroup("com.github.topjohnwu.libsu") } } } }
rootProject.name = "SpeedBackupNative"
if (providers.gradleProperty("includeProbe").isPresent) {
 include(":probe")
 project(":probe").projectDir = file("../../research/probe")
}

include(":app")
