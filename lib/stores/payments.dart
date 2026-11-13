import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/format.dart';
import '../core/native.dart';
import '../core/storage.dart';
import '../core/uuid.dart';
import '../models/models.dart';
import '../stone/stone_deeplink.dart';
import '../stone/terminal.dart';
import 'session.dart';

/// Como a forma de pagamento é cobrada na maquininha (`null` = não é: só
/// registra, como dinheiro ou "outro").
StoneTransactionType? terminalTypeFor(String canonicalMethod) => switch (canonicalMethod) {
  'credit_card' => StoneTransactionType.credit,
  'debit_card' => StoneTransactionType.debit,
  'voucher' => StoneTransactionType.voucher,
  'pix' => StoneTransactionType.pix,
  _ => null,
};

/// Opção exibida no recebimento da mesa/comanda.
class ReceiveOption {
  const ReceiveOption({required this.method, required this.label, this.isCash = false, this.isOnlinePix = false});
  final String method;
  final String label;
  final bool isCash;

  /// Pix com QR gerado pelo servidor (Mercado Pago / MT Bank).
  final bool isOnlinePix;
}

/// Formas de pagamento do PDV da loja ativa (`GET /payment-methods`).
class PaymentMethodsStore extends ChangeNotifier {
  PaymentMethodsStore(this._api);

  final Api _api;
  List<PaymentMethodOption> methods = const [];

  /// Rótulo do Pix online quando a loja tem provedor; `null` = sem Pix online.
  String? onlinePixLabel;
  bool _loaded = false;

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final data = await _api.get('/payment-methods');
      methods = asList(data['payment_methods']).map(PaymentMethodOption.fromJson).toList();
      // Servidor antigo não manda `pix_online`: mantém o Pix online de sempre.
      onlinePixLabel = !data.containsKey('pix_online')
          ? 'Pix online'
          : (data['pix_online'] is Map ? 'Pix online' : null);
      _loaded = true;
      notifyListeners();
    } on ApiException {
      // Mantém o que havia; a tela cai no padrão (dinheiro/outro).
    }
  }

  /// Opções do recebimento, na ordem da tela do PWA: Pix online primeiro,
  /// depois as formas da loja (sem crediário e sem repetir o método).
  List<ReceiveOption> get receiveOptions {
    final out = <ReceiveOption>[
      if (onlinePixLabel != null || !_loaded)
        ReceiveOption(method: 'mp_pix', label: onlinePixLabel ?? 'Pix online', isOnlinePix: true),
    ];
    if (methods.isEmpty) {
      return out
        ..add(const ReceiveOption(method: 'cash', label: 'Dinheiro', isCash: true))
        ..add(const ReceiveOption(method: 'other', label: 'Outro'));
    }
    final seen = <String>{'mp_pix', 'mt_pix'};
    for (final m in methods) {
      if (m.method == 'credit_account' || m.method == 'prepaid_wallet' || !seen.add(m.method)) continue;
      out.add(ReceiveOption(method: m.method, label: m.name, isCash: m.isCash));
    }
    return out;
  }

  void reset() {
    methods = const [];
    onlinePixLabel = null;
    _loaded = false;
  }
}

/// Transação aprovada (ou em curso) na maquininha que ainda não está
/// registrada no Mobizweb. Fica gravada no aparelho até resolver: dinheiro do
/// cliente já saiu do cartão, então nada aqui pode se perder num crash.
class PendingTef {
  PendingTef({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.label,
    required this.method,
    required this.amount,
    required this.idempotencyKey,
    required this.createdAt,
    this.state = 'inflight',
    this.atk,
    this.nsu,
    this.reference,
    this.lastError,
  });

  final String id;

  /// `session` | `comanda` | `counter`.
  final String kind;
  final String targetId;
  final String label;
  final String method;
  double amount;
  final String idempotencyKey;
  final int createdAt;

  /// `inflight` (app da Stone aberto) | `approved` (falta registrar) |
  /// `unknown` (o app fechou durante a cobrança: conferir no app da Stone).
  String state;
  String? atk;
  String? nsu;
  String? reference;
  String? lastError;

  bool get isApproved => state == 'approved';

  Json toJson() => {
    'id': id,
    'kind': kind,
    'target_id': targetId,
    'label': label,
    'method': method,
    'amount': amount,
    'idempotency_key': idempotencyKey,
    'created_at': createdAt,
    'state': state,
    'atk': atk,
    'nsu': nsu,
    'reference': reference,
    'last_error': lastError,
  };

  factory PendingTef.fromJson(Json j) => PendingTef(
    id: asString(j['id']),
    kind: asString(j['kind']),
    targetId: asString(j['target_id']),
    label: asString(j['label']),
    method: asString(j['method']),
    amount: asDouble(j['amount']),
    idempotencyKey: asString(j['idempotency_key']),
    createdAt: asInt(j['created_at']),
    state: asString(j['state'], 'unknown'),
    atk: asStringOrNull(j['atk']),
    nsu: asStringOrNull(j['nsu']),
    reference: asStringOrNull(j['reference']),
    lastError: asStringOrNull(j['last_error']),
  );
}

enum ChargeStatus {
  /// Cobrado e registrado no Mobizweb.
  recorded,

  /// Não aprovado na maquininha — nada foi cobrado.
  declined,

  /// Cobrado, mas o registro falhou: fica em "Pagamentos pendentes".
  approvedNotRecorded,

  /// A espera foi cancelada sem resposta: pode ou não ter sido cobrado.
  unknown,
}

class ChargeOutcome {
  const ChargeOutcome(this.status, [this.message, this.result]);
  final ChargeStatus status;
  final String? message;
  final StonePaymentResult? result;
}

/// Cobra na maquininha e registra no Mobizweb, sem deixar buraco entre os
/// dois passos: a transação é gravada no aparelho ANTES de abrir o app da
/// Stone e só sai da lista quando o servidor confirma o recebimento. O
/// servidor não duplica pagamento com o mesmo `tef_transaction_id`, então
/// repetir o registro é sempre seguro.
class TefLedger extends ChangeNotifier {
  TefLedger(this._api, this._store, this._terminal, this._native);

  final Api _api;
  final LocalStore _store;
  final Terminal _terminal;
  final Native _native;

  static const _key = 'tef_pending';
  List<PendingTef> pending = [];

  /// Abertura do app: recarrega a lista e concilia uma cobrança que estava em
  /// curso quando o Android encerrou o processo.
  Future<void> init() async {
    final raw = _store.getString(_key);
    if (raw != null) {
      try {
        pending = (jsonDecode(raw) as List).whereType<Map>().map((e) => PendingTef.fromJson(asMap(e))).toList();
      } catch (_) {
        pending = [];
      }
    }
    await reconcileOrphan(startup: true);
  }

  /// Lê uma resposta da Stone que chegou sem ninguém esperando (processo
  /// reiniciado, ou espera cancelada pelo operador) e aplica na cobrança em
  /// aberto mais recente. Chamado na abertura e a cada volta ao app.
  Future<void> reconcileOrphan({bool startup = false}) async {
    final orphan = await _native.takeOrphan();
    final open = pending.where((p) => p.state == 'inflight' || p.state == 'unknown').toList();
    var changed = false;
    PendingTef? approved;
    if (orphan != null && returnHost(orphan) == 'pay-response' && open.isNotEmpty) {
      final target = open.last;
      final result = parsePaymentReturn(orphan);
      if (result.approved) {
        _applyApproval(target, result);
        target.lastError = target.kind == 'counter' ? 'Venda de balcão não concluída.' : 'Aguardando registro.';
        approved = target;
      } else {
        pending.remove(target);
      }
      open.remove(target);
      changed = true;
    }
    if (startup) {
      // O que continuou "em curso" depois de um reinício tem desfecho incerto.
      for (final p in open.where((p) => p.state == 'inflight')) {
        p
          ..state = 'unknown'
          ..lastError = 'O app fechou durante a cobrança. Confira no app da Stone se foi aprovada.';
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
    if (approved != null && approved.kind != 'counter') await retry(approved);
  }

  Future<void> _save() => _store.setString(_key, jsonEncode([for (final p in pending) p.toJson()]));

  void _applyApproval(PendingTef p, StonePaymentResult r) {
    p
      ..state = 'approved'
      ..atk = r.atk
      ..nsu = r.authorizationCode
      ..reference = r.cardSummary;
    final cents = r.amountCents;
    if (cents != null && cents > 0) p.amount = cents / 100;
  }

  /// Cobra `amount` na maquininha e registra na mesa (`kind: session`) ou na
  /// comanda (`kind: comanda`).
  Future<ChargeOutcome> chargeAndRecord({
    required String kind,
    required String targetId,
    required String label,
    required String method,
    required double amount,
    required StoneTransactionType type,
  }) async {
    final entry = PendingTef(
      id: uuidV7(),
      kind: kind,
      targetId: targetId,
      label: label,
      method: method,
      amount: round2(amount),
      idempotencyKey: uuidV7(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final demo = _terminal.isDemo;
    if (!demo) {
      pending.add(entry);
      await _save();
    }

    final result = await _terminal.charge(amountCents: toCents(amount), type: type);

    if (result.code == 'abandoned') {
      // Sem resposta: a cobrança PODE ter sido aprovada. Não some da lista.
      entry
        ..state = 'unknown'
        ..lastError = 'Sem resposta da maquininha. Confira no app da Stone se a cobrança foi aprovada.';
      await _save();
      notifyListeners();
      return ChargeOutcome(ChargeStatus.unknown, entry.lastError, result);
    }

    if (!result.approved) {
      pending.remove(entry);
      await _save();
      notifyListeners();
      return ChargeOutcome(ChargeStatus.declined, result.failureMessage, result);
    }

    if (demo) {
      // Demonstração: registra como pagamento manual, sem dados de TEF.
      final error = await _record(entry);
      return error == null
          ? ChargeOutcome(ChargeStatus.recorded, null, result)
          : ChargeOutcome(ChargeStatus.declined, error, result);
    }

    _applyApproval(entry, result);
    await _save();
    final error = await _record(entry);
    if (error == null) {
      pending.remove(entry);
      await _save();
      notifyListeners();
      return ChargeOutcome(ChargeStatus.recorded, null, result);
    }
    entry.lastError = error;
    await _save();
    notifyListeners();
    return ChargeOutcome(ChargeStatus.approvedNotRecorded, error, result);
  }

  /// Só cobra (balcão): o registro acontece no checkout da venda. A transação
  /// aprovada fica na lista até [settle].
  Future<({StonePaymentResult result, PendingTef? entry})> chargeOnly({
    required String label,
    required String method,
    required double amount,
    required StoneTransactionType type,
  }) async {
    final entry = PendingTef(
      id: uuidV7(),
      kind: 'counter',
      targetId: '',
      label: label,
      method: method,
      amount: round2(amount),
      idempotencyKey: uuidV7(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final demo = _terminal.isDemo;
    if (!demo) {
      pending.add(entry);
      await _save();
    }
    final result = await _terminal.charge(amountCents: toCents(amount), type: type);
    if (result.code == 'abandoned') {
      entry
        ..state = 'unknown'
        ..lastError = 'Sem resposta da maquininha. Confira no app da Stone se a cobrança foi aprovada.';
      await _save();
      notifyListeners();
      return (result: result, entry: null);
    }
    if (!result.approved || demo) {
      pending.remove(entry);
      await _save();
      notifyListeners();
      return (result: result, entry: null);
    }
    _applyApproval(entry, result);
    entry.lastError = 'Venda de balcão não concluída.';
    await _save();
    notifyListeners();
    return (result: result, entry: entry);
  }

  /// A venda de balcão foi gravada com estas transações: saem da lista.
  Future<void> settle(Iterable<String> atks) async {
    final set = atks.toSet();
    pending.removeWhere((p) => p.atk != null && set.contains(p.atk));
    await _save();
    notifyListeners();
  }

  Future<String?> _record(PendingTef p) async {
    final path = p.kind == 'comanda' ? '/comandas/${p.targetId}/payments' : '/sessions/${p.targetId}/payments';
    try {
      await _api.post(
        path,
        body: SessionStore.paymentBody(
          method: p.method,
          amount: p.amount,
          reference: p.reference,
          tef: p.atk == null ? null : TefData(provider: Config.tefProvider, transactionId: p.atk!, nsu: p.nsu),
        ),
        idempotencyKey: p.idempotencyKey,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Tenta registrar de novo (mesma chave de idempotência e mesmo ATK).
  Future<String?> retry(PendingTef p) async {
    if (!p.isApproved || p.kind == 'counter') return 'Este pagamento não pode ser registrado automaticamente.';
    final error = await _record(p);
    if (error == null) {
      pending.remove(p);
    } else {
      p.lastError = error;
    }
    await _save();
    notifyListeners();
    return error;
  }

  /// Registra em segundo plano o que ficou pendente (volta da rede).
  Future<void> retryAll() async {
    for (final p in pending.where((p) => p.isApproved && p.kind != 'counter').toList()) {
      await retry(p);
    }
  }

  /// Estorna na maquininha e tira da lista.
  Future<String?> refund(PendingTef p) async {
    final atk = p.atk;
    if (atk == null) return 'Sem identificador da transação para estornar.';
    final r = await _terminal.refund(atk: atk, amountCents: toCents(p.amount));
    if (!r.success) return r.failureMessage;
    pending.remove(p);
    await _save();
    notifyListeners();
    return null;
  }

  /// Remove da lista sem estornar (o operador conferiu no app da Stone).
  Future<void> dismiss(PendingTef p) async {
    pending.remove(p);
    await _save();
    notifyListeners();
  }
}
