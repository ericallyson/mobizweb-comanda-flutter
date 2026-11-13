import 'package:flutter/services.dart';

import 'storage.dart';

/// Canal com o `MainActivity` (Kotlin): deeplinks da Stone, preferências,
/// token cifrado e dados do aparelho.
class Native implements KeyValueBackend {
  const Native();

  static const _ch = MethodChannel('mobiz/native');

  /// Há app da Stone para atender este deeplink? (false em celular comum.)
  Future<bool> canHandle(String uri) async {
    try {
      return await _ch.invokeMethod<bool>('available', {'uri': uri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre o deeplink e espera o retorno (`mobizpos://…`). Lança
  /// [PlatformException] com `code`: `unavailable` (sem app Stone), `busy`
  /// (já há operação em andamento) ou `failed`.
  Future<String> launch(String uri) async => (await _ch.invokeMethod<String>('launch', {'uri': uri})) ?? '';

  /// Desiste de esperar o retorno em andamento (ele vira "órfão").
  Future<void> abandon() => _ch.invokeMethod<void>('abandon');

  /// Retorno que chegou sem ninguém esperando (processo reiniciado).
  Future<String?> takeOrphan() async {
    try {
      return await _ch.invokeMethod<String>('takeOrphan');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> deviceInfo() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('deviceInfo');
      return m ?? const {};
    } catch (_) {
      return const {};
    }
  }

  // ── KeyValueBackend ───────────────────────────────────────────────────────
  @override
  Future<Map<String, String>> readAll() async {
    final m = await _ch.invokeMapMethod<String, String?>('prefsAll') ?? const {};
    return {
      for (final e in m.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  @override
  Future<void> write(String key, String? value) => _ch.invokeMethod<void>('prefsSet', {'key': key, 'value': value});

  @override
  Future<String?> secureRead(String key) async {
    try {
      return await _ch.invokeMethod<String>('secureRead', {'key': key});
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> secureWrite(String key, String? value) async {
    try {
      await _ch.invokeMethod<void>('secureWrite', {'key': key, 'value': value});
    } catch (_) {
      // Sem Keystore o token vive só em memória.
    }
  }
}
