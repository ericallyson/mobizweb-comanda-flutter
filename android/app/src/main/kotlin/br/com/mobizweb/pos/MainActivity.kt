package br.com.mobizweb.pos

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Ponte dos deeplinks da Stone (pagamento, cancelamento, impressão e
 * reimpressão). O app NÃO usa o SDK da Stone: dispara `Intent.ACTION_VIEW`
 * para os apps Stone do terminal e recebe a resposta num deeplink de retorno
 * (`mobizpos://<host>?…`) em `onNewIntent`.
 *
 * A montagem da URI e a leitura da resposta ficam em Dart
 * (`lib/stone/stone_deeplink.dart`), onde têm teste; aqui só há transporte.
 *
 * O mesmo canal guarda as preferências do app e o token de acesso (cifrado
 * com chave do Android Keystore). É de propósito que não há plugin para isso:
 * cada plugin a menos é APK menor e manifest mais fácil de auditar para a
 * homologação.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureReturn(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureReturn(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(canHandle(call.argument<String>("uri") ?: "payment-app://pay"))
            "launch" -> launch(call.argument<String>("uri"), result)
            "takeOrphan" -> {
                result.success(orphan)
                orphan = null
            }
            "abandon" -> {
                // O Dart desistiu de esperar: se a resposta chegar depois,
                // vira órfã e é conciliada na próxima leitura.
                val waiter = pending
                pending = null
                waiter?.error("abandoned", "Espera cancelada pelo operador.", null)
                result.success(null)
            }
            "deviceInfo" -> result.success(
                mapOf(
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "sdkInt" to Build.VERSION.SDK_INT,
                    "release" to Build.VERSION.RELEASE,
                    "filesDir" to filesDir.absolutePath,
                ),
            )
            "prefsAll" -> result.success(prefs().all.mapValues { it.value?.toString() })
            "prefsSet" -> {
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                if (key != null) {
                    // commit (síncrono): a cobrança em curso é gravada aqui
                    // ANTES de o app da Stone abrir e não pode se perder.
                    prefs().edit().apply { if (value == null) remove(key) else putString(key, value) }.commit()
                }
                result.success(null)
            }
            "secureRead" -> result.success(secureRead(call.argument<String>("key") ?: ""))
            "secureWrite" -> {
                secureWrite(call.argument<String>("key") ?: "", call.argument<String>("value"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Preferências ────────────────────────────────────────────────────────

    private fun prefs() = getSharedPreferences("mobiz_prefs", Context.MODE_PRIVATE)

    private fun securePrefs() = getSharedPreferences("mobiz_secure", Context.MODE_PRIVATE)

    // ── Token cifrado (AES-256/GCM, chave no Android Keystore) ──────────────

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun secureWrite(key: String, value: String?) {
        if (key.isEmpty()) return
        if (value == null) {
            securePrefs().edit().remove(key).apply()
            return
        }
        try {
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val packed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            securePrefs().edit().putString(key, Base64.encodeToString(packed, Base64.NO_WRAP)).apply()
        } catch (_: Exception) {
            // Keystore indisponível: não grava em claro. O operador entra de
            // novo na próxima abertura do app.
            securePrefs().edit().remove(key).apply()
        }
    }

    private fun secureRead(key: String): String? {
        val stored = securePrefs().getString(key, null) ?: return null
        return try {
            val packed = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, packed, 0, GCM_IV_BYTES))
            String(cipher.doFinal(packed, GCM_IV_BYTES, packed.size - GCM_IV_BYTES), Charsets.UTF_8)
        } catch (_: Exception) {
            // Chave perdida (restauração de fábrica do Keystore etc.): descarta.
            securePrefs().edit().remove(key).apply()
            null
        }
    }

    private fun canHandle(uri: String): Boolean = try {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        @Suppress("DEPRECATION")
        packageManager.queryIntentActivities(probe, 0).isNotEmpty()
    } catch (_: Exception) {
        false
    }

    private fun launch(uri: String?, result: MethodChannel.Result) {
        if (uri.isNullOrEmpty()) {
            result.error("invalid", "URI vazia.", null)
            return
        }
        if (pending != null) {
            result.error("busy", "Já existe uma operação em andamento na maquininha.", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            pending = result
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            pending = null
            result.error("unavailable", "Aplicativo da Stone não encontrado neste aparelho.", null)
        } catch (e: Exception) {
            pending = null
            result.error("failed", e.message ?: "Falha ao abrir o aplicativo da Stone.", null)
        }
    }

    private fun captureReturn(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != RETURN_SCHEME) return
        val raw = data.toString()
        // Consome: recriar a Activity (rotação, tema) não pode reentregar.
        intent.data = null
        val waiter = pending
        if (waiter != null) {
            pending = null
            waiter.success(raw)
        } else {
            orphan = raw
        }
    }

    companion object {
        private const val CHANNEL = "mobiz/native"

        // Do PROCESSO, não da instância: se o Android recriar a Activity para
        // entregar o retorno, quem espera a resposta continua sendo achado.

        /** Chamada `launch` do Dart aguardando o deeplink de retorno. */
        private var pending: MethodChannel.Result? = null

        /**
         * Resposta que chegou sem ninguém esperando: o Android matou o
         * processo enquanto o app da Stone estava em primeiro plano (terminal
         * com pouca memória) e o retorno abriu o app do zero. O Dart busca com
         * `takeOrphan` na abertura e concilia o pagamento.
         */
        private var orphan: String? = null

        /** O mesmo `android:scheme` dos intent-filters do AndroidManifest. */
        private const val RETURN_SCHEME = "mobizpos"

        private const val KEY_ALIAS = "mobiz_pos_token"
        private const val AES_GCM = "AES/GCM/NoPadding"
        private const val GCM_IV_BYTES = 12
    }
}
