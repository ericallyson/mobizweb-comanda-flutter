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
      },
      idempotencyKey: idempotencyKey,
    );
    return CounterSaleResult.fromJson(data);
  }

  void reset() {
    context = null;
    loading = false;
    error = null;
    notifyListeners();
  }
}
