import 'package:flutter/services.dart';

import 'storage.dart';

/// Como terminou a leitura de QR pela câmera ([Native.scanQr]).
enum QrScanStatus {
  /// Leu: o conteúdo está em [QrScan.text].
  read,

  /// O operador voltou sem ler.
  canceled,

  /// O aparelho não tem câmera.
  noCamera,

  /// O operador negou a permissão da câmera.
  denied,

  /// Não há leitor aqui (prévia web, testes) ou a câmera não abriu.
  unavailable,
}

class QrScan {
  const QrScan(this.status, [this.text]);
  final QrScanStatus status;
  final String? text;
}

/// Canal com o `MainActivity` (Kotlin): deeplinks da Stone, preferências,
/// token cifrado, dados do aparelho, leitor de QR (câmera) e imagem de QR.
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

  /// Abre o leitor de QR do aparelho (câmera traseira, em retrato) e espera
  /// o operador ler ou voltar. Nunca lança: onde o canal não existe (prévia
  /// web, testes) devolve [QrScanStatus.unavailable].
  Future<QrScan> scanQr({String? prompt}) async {
    try {
      final text = await _ch.invokeMethod<String>('scanQr', {'prompt': ?prompt});
      return (text == null || text.isEmpty) ? const QrScan(QrScanStatus.canceled) : QrScan(QrScanStatus.read, text);
    } on PlatformException catch (e) {
      return QrScan(switch (e.code) {
        'no_camera' => QrScanStatus.noCamera,
        'denied' => QrScanStatus.denied,
        _ => QrScanStatus.unavailable,
      });
    } catch (_) {
      return const QrScan(QrScanStatus.unavailable);
    }
  }

  /// PNG do QR de [text] com [size] px de lado, desenhado no lado nativo.
  /// `null` onde não há como gerar (prévia web, testes): a tela mostra só o
  /// código.
  Future<Uint8List?> qrPng(String text, {int size = 480}) async {
    try {
      return await _ch.invokeMethod<Uint8List>('qrPng', {'text': text, 'size': size});
    } catch (_) {
      return null;
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
