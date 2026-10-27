plugins { id("com.android.application") version "9.1.0" }
android {
    namespace = "dev.marionette.nativeui"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.marionette.nativeui"
        minSdk = 26
        targetSdk = 36
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
dependencies {
    androidTestImplementation("androidx.test:runner:1.5.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    androidTestImplementation("junit:junit:4.13.2")
}
