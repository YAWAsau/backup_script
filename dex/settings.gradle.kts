pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("third_party/maven"); content { includeGroup("com.google.code.gson"); includeGroup("org.lsposed.hiddenapibypass") } }
        google()
        mavenCentral()
    }
}

rootProject.name = "Script Dex"
include(":app")
include(":hiddenapi")
