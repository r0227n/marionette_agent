plugins { id("com.android.application") }
android {
    namespace = "dev.marionette.capture"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.marionette.capture"
        minSdk = 26
        targetSdk = 36
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        val config = System.getenv("MARIONETTE_CAPTURE_PAIRING")
        if (config != null) {
            val pairing = groovy.json.JsonSlurper().parse(file(config)) as Map<*, *>
            testInstrumentationRunnerArguments["captureDevice"] = pairing["device"].toString()
            testInstrumentationRunnerArguments["capturePort"] = pairing["port"].toString()
            testInstrumentationRunnerArguments["captureToken"] = pairing["token"].toString()
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
dependencies {
    androidTestImplementation("androidx.test:runner:1.5.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    androidTestImplementation("junit:junit:4.13.2")
}
