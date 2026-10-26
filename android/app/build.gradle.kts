import java.io.FileInputStream
import java.util.Properties
import java.util.Base64
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
// Use exactly Flutter's compile-time environment; no debug/release fallback.
val firebaseDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8).split("=", limit = 2)
        }.getOrNull()?.takeIf { it.size == 2 }?.let { it[0] to it[1] }
    }.toMap()
val firebaseEnvironment = firebaseDefines["FIREBASE_ENV"]
val firebaseResources = mutableMapOf<String, String>()
if (firebaseEnvironment in listOf("dev", "prod")) {
    val configFile = rootProject.file("../config/firebase/$firebaseEnvironment/google-services.json")
    if (configFile.exists() && !firebaseDefines["FIREBASE_ANDROID_API_KEY"].isNullOrEmpty()) {
        val config = JsonSlurper().parse(configFile) as Map<*, *>
        val info = config["project_info"] as Map<*, *>
        val client = (config["client"] as List<*>).single() as Map<*, *>
        val identity = client["client_info"] as Map<*, *>
        val key = ((client["api_key"] as List<*>).first() as Map<*, *>)["current_key"] as String
        val dev = firebaseEnvironment == "dev"
        require(info["project_id"] == if (dev) "clean-stream-dev" else "clean-stream-production")
        require(identity["mobilesdk_app_id"] == if (dev)
            "1:83380736317:android:7b074a257825c9670af554" else
            "1:863183154828:android:3c15f3dbc067244de615a9")
        require(key == firebaseDefines["FIREBASE_ANDROID_API_KEY"]) { "Firebase native/Dart key mismatch" }
        firebaseResources.putAll(mapOf("google_app_id" to identity["mobilesdk_app_id"] as String,
            "google_api_key" to key, "gcm_defaultSenderId" to info["project_number"] as String,
            "project_id" to info["project_id"] as String))
    }
}
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.cleanstreamlaundrysolutions.clean_stream_laundry_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.cleanstreamlaundrysolutions.clean_stream_laundry_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        firebaseResources.forEach { (name, value) -> resValue("string", name, value) }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.material:material:1.11.0")
}

flutter {
    source = "../.."
}
