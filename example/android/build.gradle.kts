allprojects {
    repositories {
        // Local build of the MapZone Speed Alert SDK — kept commented; testing
        // against the published 2.0.1 package on JitPack instead. Publish with:
        //   cd map-sdk-tracking/android && ./gradlew :mapzone-speed-alert-sdk:publishToMavenLocal
        // mavenLocal()
        google()
        mavenCentral()
        // JitPack hosts the published MapZone/VietMap SDKs.
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
