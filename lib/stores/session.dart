import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Credenciais do gerente que libera uma ação sensível (a loja decide quais
/// exigem). Nunca são persistidas.
class ManagerOverride {
  const ManagerOverride(this.email, this.password);
  final String email;
  final String password;

  Json toJson() => (email.trim().isEmpty && password.isEmpty)
      ? const {}
      : {'override_email': email.trim(), 'override_password': password};
}

/// Dados da transação cobrada na maquininha, enviados junto do pagamento
/// (`docs/api-comanda.md` §7 — TEF na maquininha).
class TefData {
  const TefData({required this.provider, required this.transactionId, this.nsu});
  final String provider;
  final String transactionId;
  final String? nsu;

  Json toJson() => {'tef_provider': provider, 'tef_transaction_id': transactionId, 'tef_nsu': ?nsu};
}

/// Resultado do envio do carrinho.
class SendCartResult {
  const SendCartResult({this.error, this.kitchenSent = true, this.orderCode});

  /// `null` = pedido gravado.
  final String? error;

  /// `false` = gravado, mas a produção não recebeu (não reenviar).
  final bool kitchenSent;
  final String? orderCode;
  bool get ok => error == null;
}

/// A mesa aberta na tela: conta, itens, comandas e todas as ações sobre ela.
/// Junta `stores/session.ts` e `stores/comanda.ts` do PWA.
///
/// Convenção: as ações devolvem `null` no sucesso ou a mensagem de erro já
/// pronta para a tela (o backend manda o motivo em `error`).
class SessionStore extends ChangeNotifier {
  SessionStore(this._api);

  final Api _api;

  SessionDetail? session;
  bool loading = false;
  String? error;

  // Comandas da sessão (carregadas sob demanda pela tela de comandas).
  List<Comanda> comandas = const [];
  List<({String id, String label})> availableComandas = const [];
  List<ComandaTransferTable> transferTables = const [];
  bool transferRequiresPassword = false;
  bool cancelRequiresPassword = false;
  bool comandasLoading = false;

  String? _loadingId;

  void clear() {
    session = null;
    error = null;
    comandas = const [];
    availableComandas = const [];
    transferTables = const [];
    notifyListeners();
  }

  Future<void> fetch(String sessionId, {bool silent = false}) async {
    _loadingId = sessionId;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final data = await _api.get('/sessions/$sessionId');
      if (_loadingId != sessionId) return; // resposta de outra mesa
      session = SessionDetail.fromJson(asMap(data['session']));
      error = null;
    } on ApiException catch (e) {
      if (_loadingId != sessionId) return;
      if (session?.id != sessionId) {
        session = null;
        error = e.isNetwork ? 'Sem conexão. Não foi possível carregar a comanda.' : 'Não foi possível carregar a comanda.';
      }
    } finally {
      if (_loadingId == sessionId) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<String?> _run(Future<void> Function() action, {bool refetch = true}) async {
    try {
      await action();
      final id = session?.id;
      if (refetch && id != null) await fetch(id, silent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  // ── Pedido ────────────────────────────────────────────────────────────────

  /// Envia o carrinho. `idempotencyKey` é ESTÁVEL por carrinho: repetir o
  /// envio depois de um timeout devolve a resposta original, sem duplicar.
  Future<SendCartResult> sendCart(
    String sessionId,
    List<CartItem> items, {
    String? comandaId,
    required String idempotencyKey,
  }) async {
    try {
      final data = await _api.post(
        '/sessions/$sessionId/orders',
        body: {
          'items': [for (final i in items) i.toPayload()],
          'session_comanda_id': comandaId,
        },
        idempotencyKey: idempotencyKey,
      );
      await fetch(sessionId, silent: true);
      return SendCartResult(
        kitchenSent: data['kitchen_sent'] != false,
        orderCode: asStringOrNull(asMap(data['order'])['code']),
      );
    } on ApiException catch (e) {
      if (e.isTransient) {
        return const SendCartResult(
          error: 'Sem resposta do servidor. Toque em Enviar de novo: o pedido não será duplicado.',
        );
      }
      final reason = e.isValidation ? Api.reasonOf(e.body) : null;
      return SendCartResult(
        error: reason != null ? 'Não foi possível enviar o pedido: $reason' : 'Não foi possível enviar o pedido.',
      );
    }
  }

  Future<String?> approveTabletOrder(String orderId) => _run(() => _api.post('/tablet/orders/$orderId/approve'));

  // ── Itens ─────────────────────────────────────────────────────────────────

  Future<String?> cancelItem(String itemId, String reason) =>
      _run(() => _api.delete('/items/$itemId', body: {'reason': reason}));

  /// Transfere item(ns) para outra mesa/comanda. `targetTableId` = mesa
  /// livre (abre e transfere); senão `targetSessionId` (+ comanda opcional).
  Future<String?> transferItems(
    List<String> itemIds, {
    String? targetSessionId,
    String? targetTableId,
    String? targetComandaId,
    int? quantity,
    ManagerOverride? override,
  }) {
    final body = <String, dynamic>{
      'target_table_id': ?targetTableId,
      if (targetTableId == null) 'target_session_id': targetSessionId,
      if (targetTableId == null) 'target_comanda_id': targetComandaId,
      ...?override?.toJson(),
    };
    return _run(() async {
      if (itemIds.length > 1) {
        await _api.post('/sessions/${session!.id}/items/transfer', body: {...body, 'items': itemIds});
      } else {
        await _api.post('/items/${itemIds.first}/transfer', body: {...body, 'quantity': ?quantity});
      }
    });
  }

  // ── Mesa ──────────────────────────────────────────────────────────────────

  Future<String?> updateCustomer(String? name) =>
      _run(() => _api.patch('/sessions/${session!.id}/customer', body: {'customer_name': name}));

  /// Pede a conta: a mesa vai para "fechando".
  Future<String?> requestBill() {
    final tableId = session?.tableId;
    if (tableId == null) return Future.value('Mesa não carregada.');
    return _run(() => _api.post('/tables/$tableId/sessions/current/bill'));
  }

  Future<String?> reopen() => _run(() => _api.post('/sessions/${session!.id}/reopen'));

  Future<String?> cancelSession({ManagerOverride? override}) =>
      _run(() => _api.post('/sessions/${session!.id}/cancel', body: {...?override?.toJson()}), refetch: false);

  /// Fechamento explícito (conta quitada e mesa ainda aberta). `print: false`
  /// porque quem imprime aqui é a maquininha, não a Bridge.
  Future<String?> closeSession() =>
      _run(() => _api.post('/sessions/${session!.id}/close', body: {'print': false}));

  Future<String?> transferTable(String targetTableId) => _run(
    () => _api.post('/sessions/${session!.id}/transfer', body: {'target_table_id': targetTableId}),
    refetch: false,
  );

  /// "Gerar QR do tablet na mesa": código de 6 dígitos que o cliente lê ou
  /// digita no tablet para abrir esta mesa nele. Gerar de novo substitui o
  /// código anterior. Mesma rota do PWA (`TabletCodeModal.vue`). Lança
  /// [ApiException].
  Future<({String code, String? tableNumber})> generateTabletCode() async {
    final data = await _api.post('/sessions/${session!.id}/tablet-code');
    return (code: asString(data['code']), tableNumber: asStringOrNull(data['table_number']));
  }

  // ── Couvert ───────────────────────────────────────────────────────────────

  Future<String?> setCouvert(double amount, int persons) =>
      _run(() => _api.post('/sessions/${session!.id}/couvert', body: {'amount': amount, 'persons': persons}));

  Future<String?> removeCouvert() => _run(() => _api.delete('/sessions/${session!.id}/couvert'));

  /// Mesa com comandas: valor por pessoa + pessoas de cada comanda.
  Future<String?> setComandaCouvert(double amount, List<({String id, int persons})> list) => _run(
    () => _api.post(
      '/sessions/${session!.id}/couvert',
      body: {
        'amount': amount.toStringAsFixed(2),
        'comandas': [
          for (final c in list) {'id': c.id, 'persons': c.persons},
        ],
      },
    ),
  );

  Future<String?> removeComandaCouvert(String comandaId) => _run(() => _api.delete('/comandas/$comandaId/couvert'));

  // ── Recebimento da mesa ───────────────────────────────────────────────────

  /// Registra um pagamento na conta da mesa. `method` é o canônico da forma
  /// (`cash`, `credit_card`…). Dinheiro exige `cashReceived`.
  Future<String?> payTable({
    required String method,
    required double amount,
    double? cashReceived,
    String? pixChargeId,
    TefData? tef,
    String? reference,
    String? idempotencyKey,
  }) => _run(
    () => _api.post(
      '/sessions/${session!.id}/payments',
      body: paymentBody(
        method: method,
        amount: amount,
        cashReceived: cashReceived,
        pixChargeId: pixChargeId,
        tef: tef,
        reference: reference,
      ),
      idempotencyKey: idempotencyKey,
    ),
  );

  static Json paymentBody({
    required String method,
    required double amount,
    double? cashReceived,
    String? pixChargeId,
    TefData? tef,
    String? reference,
  }) => {
    'method': method,
    'amount': amount,
    'cash_received': ?cashReceived,
    'mp_payment_id': ?pixChargeId,
    'reference': ?reference,
    ...?tef?.toJson(),
  };

  /// QR Pix do saldo (provedor escolhido pelo servidor). Lança [ApiException].
  Future<PixCharge> generateTablePix(double amount) async =>
      PixCharge.fromJson(await _api.post('/sessions/${session!.id}/pix', body: {'amount': amount}));

  Future<PixCharge> generateComandaPix(String comandaId, double amount) async =>
      PixCharge.fromJson(await _api.post('/comandas/$comandaId/pix', body: {'amount': amount}));

  /// `true` = pago. Erro de rede/provedor conta como "ainda não".
  Future<bool> pixPaid(String chargeId) async {
    try {
      final data = await _api.get('/comanda-pix/$chargeId/status');
      return asBool(data['paid']);
    } on ApiException {
      return false;
    }
  }

  /// Payload estruturado da conta para imprimir na térmica do terminal.
  Future<Json> fetchReceipt() async => asMap((await _api.get('/sessions/${session!.id}/receipt'))['receipt']);

  // ── Comandas ──────────────────────────────────────────────────────────────

  Future<String?> loadComandas() async {
    final id = session?.id;
    if (id == null) return 'Mesa não carregada.';
    comandasLoading = true;
    notifyListeners();
    try {
      final r = ComandasResponse.fromJson(await _api.get('/sessions/$id/comandas'));
      if (session?.id != id) return null;
      comandas = r.comandas;
      availableComandas = r.available;
      transferTables = r.transferTables;
      transferRequiresPassword = r.transferRequiresPassword;
      cancelRequiresPassword = r.cancelRequiresPassword;
      return null;
    } on ApiException catch (e) {
      return e.isNetwork ? e.message : 'Não foi possível carregar as comandas.';
    } finally {
      comandasLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _comanda(Future<void> Function() action) async {
    try {
      await action();
      await loadComandas();
      final id = session?.id;
      if (id != null) await fetch(id, silent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> attachComanda({String? comandaTableId, String? label}) => _comanda(
    () => _api.post(
      '/sessions/${session!.id}/comandas',
      body: comandaTableId != null ? {'comanda_table_id': comandaTableId} : {'label': label},
    ),
  );

  Future<String?> renameComanda(String id, String label) =>
      _comanda(() => _api.patch('/comandas/$id', body: {'label': label}));

  Future<String?> removeComanda(String id) => _comanda(() => _api.delete('/comandas/$id'));

  Future<String?> requestComandaBill(String id) => _comanda(() => _api.post('/comandas/$id/bill'));

  Future<String?> reopenComanda(String id) => _comanda(() => _api.post('/comandas/$id/reopen'));

  Future<String?> cancelComandaItems(String id, String reason, {ManagerOverride? override}) =>
      _comanda(() => _api.post('/comandas/$id/cancel-items', body: {'reason': reason, ...?override?.toJson()}));

  Future<String?> removeComandaFee(String id, {ManagerOverride? override}) =>
      _comanda(() => _api.post('/comandas/$id/service-fee/remove', body: {...?override?.toJson()}));

  Future<String?> reapplyComandaFee(String id) => _comanda(() => _api.post('/comandas/$id/service-fee/reapply'));

  /// Transfere a comanda para outra mesa. Devolve o erro (ou `null`) e se a
  /// mesa de ORIGEM foi encerrada (a comanda era a última).
  Future<({String? error, bool originEnded})> transferComanda(
    String id,
    String targetTableId, {
    ManagerOverride? override,
  }) async {
    try {
      final data = await _api.post(
        '/comandas/$id/transfer',
        body: {'target_table_id': targetTableId, ...?override?.toJson()},
      );
      final status = asString(asMap(data['origin_session'])['status']);
      final ended = status.isNotEmpty && status != 'open' && status != 'closing';
      if (!ended) {
        await loadComandas();
        final sid = session?.id;
        if (sid != null) await fetch(sid, silent: true);
      }
      return (error: null, originEnded: ended);
    } on ApiException catch (e) {
      return (error: e.message, originEnded: false);
    }
  }

  Future<String?> payComanda(
    String comandaId, {
    required String method,
    required double amount,
    double? cashReceived,
    String? pixChargeId,
    TefData? tef,
    String? reference,
    String? idempotencyKey,
  }) => _comanda(
    () => _api.post(
      '/comandas/$comandaId/payments',
      body: paymentBody(
        method: method,
        amount: amount,
        cashReceived: cashReceived,
        pixChargeId: pixChargeId,
        tef: tef,
        reference: reference,
      ),
      idempotencyKey: idempotencyKey,
    ),
  );
}
