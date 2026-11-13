import 'dart:convert';
import 'dart:io';

import '../models/json.dart';

/// Onde as preferências e o token moram de verdade. No aparelho é o canal
/// nativo (`NativeBackend`); nos testes, memória.
abstract class KeyValueBackend {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String? value);
  Future<String?> secureRead(String key);
  Future<void> secureWrite(String key, String? value);
}

class MemoryBackend implements KeyValueBackend {
  final Map<String, String> values = {};
  final Map<String, String> secure = {};

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
  @override
  Future<String?> secureRead(String key) async => secure[key];
  @override
  Future<void> secureWrite(String key, String? value) async =>
      value == null ? secure.remove(key) : secure[key] = value;
}

/// Persistência local do aparelho:
///  - preferências e sessão → SharedPreferences nativo (lidas uma vez na
///    abertura; leitura síncrona depois);
///  - token do Sanctum → cifrado com chave do Android Keystore;
///  - cache de cardápio/mesas (JSON grande) → arquivos em `files/cache_api`.
class LocalStore {
  LocalStore._(this._backend, this._values, this._dir);

  final KeyValueBackend _backend;
  final Map<String, String> _values;
  final Directory? _dir;
  static const _tokenKey = 'auth_token';

  /// `filesDir` nulo (testes) desliga o cache em arquivo.
  static Future<LocalStore> open(KeyValueBackend backend, {String? filesDir}) async {
    Directory? dir;
    if (filesDir != null) {
      dir = Directory('$filesDir/cache_api');
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
    return LocalStore._(backend, await backend.readAll(), dir);
  }

  // ── Preferências ──────────────────────────────────────────────────────────
  String? getString(String key) => _values[key];

  Future<void> setString(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    return _backend.write(key, value);
  }

  bool getBool(String key, bool fallback) {
    final v = _values[key];
    return v == null ? fallback : v == '1';
  }

  Future<void> setBool(String key, bool value) => setString(key, value ? '1' : '0');

  int getInt(String key, int fallback) => int.tryParse(_values[key] ?? '') ?? fallback;
  Future<void> setInt(String key, int value) => setString(key, '$value');

  Json? getJson(String key) {
    final raw = _values[key];
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map ? v.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Json? value) => setString(key, value == null ? null : jsonEncode(value));

  // ── Token ─────────────────────────────────────────────────────────────────
  Future<String?> readToken() => _backend.secureRead(_tokenKey);
  Future<void> writeToken(String? token) => _backend.secureWrite(_tokenKey, token);

  // ── Cache em arquivo ──────────────────────────────────────────────────────
  File? _file(String name) => _dir == null ? null : File('${_dir.path}/$name.json');

  Future<void> writeCache(String name, Object data) async {
    try {
      await _file(name)?.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // Cache é conveniência: disco cheio não pode quebrar a operação.
    }
  }

  Future<dynamic> readCache(String name) async {
    try {
      final f = _file(name);
      if (f == null || !f.existsSync()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      for (final f in _dir?.listSync() ?? const <FileSystemEntity>[]) {
        f.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}
