import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura: `android/key.properties` (fora do git) aponta para a JKS.
//   storeFile=/caminho/mobiz-pos.jks  storePassword=…  keyAlias=…  keyPassword=…
// Sem o arquivo, o release sai com a chave de debug — serve para testar na
// maquininha de desenvolvimento, NÃO para homologar. Ver docs/stone.md.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
val hasReleaseKey = keystoreFile.exists()
if (hasReleaseKey) {
    keystoreFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // packageName segue a regra da Stone (br.com.<empresa>.<app>, sem "stone",
    // sem fabricante/modelo de terminal) e NUNCA pode mudar depois de
    // homologado: packageName + keystore identificam o app no TMS.
    namespace = "br.com.mobizweb.pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.mobizweb.pos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Terminais Stone são ARM. O build (tool/build.*) passa
        // `--target-platform android-arm,android-arm64`; o filtro abaixo
        // garante o mesmo para qualquer biblioteca nativa de plugin.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // A Stone exige V1 (JAR) E V2 (Full APK). Com minSdk >= 24 o
                // AGP desligaria a V1 sozinho — por isso é explícito.
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    // Bibliotecas nativas COMPRIMIDAS dentro do APK: o arquivo fica com menos
    // da metade do tamanho (limite da Stone: 70 MB; atualização chega pelo chip).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            // `signDebug=true` no key.properties (tool/maquininha.ps1 grava):
            // assina também o build de DEBUG com a chave configurada — é o
            // que os terminais de debug da Gertec/Positivo exigem.
            if (hasReleaseKey && keystoreProperties.getProperty("signDebug") == "true") {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Leitor de QR pela câmera ("Ler QR da comanda") e gerador do QR do
    // tablet. É ZXing puro, SEM Google Play Services (proibido no terminal
    // Stone); traz `com.google.zxing:core`. O canal fica no MainActivity.
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
}
