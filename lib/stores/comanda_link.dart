import '../core/api.dart';
import '../models/models.dart';

/// O código que vai para o servidor a partir do que a câmera leu no QR da
/// comanda. Igual ao `ComandaScanModal.vue` do PWA: o conteúdo do QR inteiro,
/// só sem os espaços das pontas (quem interpreta é o servidor, em
/// `POST /tablet/comandas/lookup`). `null` = leitura vazia.
String? comandaCodeFromQr(String? raw) {
  final code = raw?.trim() ?? '';
  return code.isEmpty ? null : code;
}

/// "Ler QR da comanda": diz a que MESA pertence um cartão/comanda. Mesmos
/// endpoints do `ComandaScanModal.vue` do PWA. O código vem da câmera
/// (`Native.scanQr` + [comandaCodeFromQr]) ou é digitado.
class ComandaLinkStore {
  ComandaLinkStore(this._api);

  final Api _api;

  /// `POST /tablet/comandas/lookup`. Lança [ComandaLinkException] com a
  /// mensagem do servidor (ex.: "Comanda não encontrada nesta loja.").
  Future<ComandaLookup> lookup(String code) async {
    try {
      return ComandaLookup.fromJson(await _api.post('/tablet/comandas/lookup', body: {'code': code.trim()}));
    } on ApiException catch (e) {
      throw ComandaLinkException(_message(e, 'Comanda não encontrada nesta loja.'));
    }
  }

  /// `POST /tablet/comandas/link`. Devolve o número da mesa em que a comanda
  /// ficou (a mesa é aberta pelo servidor se estiver livre).
  Future<String?> link(String code, String tableId) async {
    try {
      final data = await _api.post('/tablet/comandas/link', body: {'code': code.trim(), 'table_id': tableId});
      return asStringOrNull(asMap(data['link'])['table_number']);
    } on ApiException catch (e) {
      throw ComandaLinkException(_message(e, 'Não foi possível vincular a comanda.'));
    }
  }

  /// O servidor explica o motivo em `message` (inclusive no 409, "já está
  /// vinculada à mesa N"); sem resposta, vale a mensagem de rede do [Api].
  static String _message(ApiException e, String fallback) {
    if (e.isNetwork) return e.message;
    return Api.reasonOf(e.body) ?? (e.status == 404 ? fallback : e.message);
  }
}

class ComandaLinkException implements Exception {
  ComandaLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}
