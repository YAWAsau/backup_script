pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "SpeedBackupNative"
if (providers.gradleProperty("includeProbe").isPresent) {
 include(":probe")
 project(":probe").projectDir = file("../../research/probe")
}

include(":app")
