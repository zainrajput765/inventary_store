allprojects {
    repositories {
        google()
        mavenCentral()
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

// --- FIX FOR ISAR, PATH_PROVIDER & NEWER ANDROID BUILDS ---
// This forces all plugins to use a compatible SDK version
subprojects {
    if (project.name != "app") {
        project.afterEvaluate {
            val android = project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            if (android != null) {
                // Force Compile SDK to 35 (Stable for current plugins)
                android.compileSdkVersion(35)

                android.defaultConfig {
                    targetSdkVersion(35)
                }

                // Fix 'Namespace not specified' error for older plugins
                if (android.namespace == null) {
                    android.namespace = "com.example.${project.name.replace('-', '_')}"
                }
            }
        }
    }
}