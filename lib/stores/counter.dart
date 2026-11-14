import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Uma parcela do recebimento da venda de balcão.
class CounterPayment {
  const CounterPayment({required this.method, required this.label, required this.amount, this.atk, this.nsu});

  /// Método canônico (`cash`, `credit_card`…).
  final String method;
  final String label;
  final double amount;

  /// Preenchidos quando a parcela foi cobrada na maquininha.
  final String? atk;
  final String? nsu;

  bool get charged => atk != null;

  Json toJson() => {'method': method, 'amount': amount, 'tef_transaction_id': ?atk, 'tef_nsu': ?nsu};
}

/// Venda de balcão. 100% ONLINE por decisão de produto (igual ao PWA): o que
/// protege contra rede instável é a Idempotency-Key ESTÁVEL por carrinho —
/// repetir o "Receber" devolve a resposta original em vez de duplicar.
class CounterStore extends ChangeNotifier {
  CounterStore(this._api);

  final Api _api;

  CounterContext? context;
  bool loading = false;
  String? error;

  Future<void> fetchContext() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      context = CounterContext.fromJson(await _api.get('/counter/context'));
    } on ApiException catch (e) {
      error = e.isNetwork ? 'A venda de balcão exige conexão com o servidor.' : 'Não foi possível carregar o balcão.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Lança [ApiException] — a tela decide a mensagem (rede × regra).
  Future<CounterSaleResult> checkout(
    List<CartItem> items,
    List<CounterPayment> payments, {
    String? customerName,
    required String idempotencyKey,
  }) async {
    final data = await _api.post(
      '/counter/checkout',
      body: {
        'items': [for (final i in items) i.toPayload()],
        'payments': [for (final p in payments) p.toJson()],
        if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
        // Loja fiscal: a venda fecha SEM nota; a NFC-e sai só quando o
        // operador toca em "Imprimir nota fiscal" ([issueFiscal]).
        if (context?.fiscalActive ?? false) 'non_fiscal': true,
      },
      idempotencyKey: idempotencyKey,
    );
    return CounterSaleResult.fromJson(data);
  }

  /// Emite a NFC-e de uma venda de balcão já concluída e devolve o DANFE.
  /// Pedir de novo devolve a MESMA nota (segunda via), nunca emite outra.
  /// Lança [ApiException]: nota rejeitada vem com o motivo da SEFAZ.
  Future<FiscalNote> issueFiscal(String orderId, {required String idempotencyKey}) async =>
      FiscalNote.fromJson(await _api.post('/counter/orders/$orderId/fiscal', idempotencyKey: idempotencyKey));

  void reset() {
    context = null;
    loading = false;
    error = null;
    notifyListeners();
  }
}
