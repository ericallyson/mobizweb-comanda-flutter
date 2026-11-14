/// O recebimento, sem tela: as regras que antes moravam nas folhas
/// "Receber conta" (mesa e comanda) e "Receber venda" (balcão). A tela
/// `ReceiveScreen` só desenha o que o controlador diz e chama [receive].
///
/// NADA aqui é regra nova: são as mesmas validações, as mesmas rotinas
/// (`SessionStore.payTable`/`payComanda`, `TefLedger.chargeAndRecord`/
/// `chargeOnly`, `CounterStore.checkout`) e as mesmas mensagens de antes.
library;

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../stone/terminal.dart';
import 'counter.dart';
import 'payments.dart';
import 'session.dart';

/// Uma forma de pagamento na grade da tela.
class ReceiveMethod {
  const ReceiveMethod({
    required this.id,
    required this.method,
    required this.label,
    this.isCash = false,
    this.isOnlinePix = false,
  });

  /// O que identifica a escolha: o método canônico (mesa e comanda) ou o
  /// código cadastrado na loja (balcão).
  final String id;

  /// Método canônico (`cash`, `credit_card`, `pix`...). Define o ícone e se a
  /// forma é cobrada na maquininha.
  final String method;
  final String label;
  final bool isCash;

  /// Pix com QR gerado pelo servidor.
  final bool isOnlinePix;
}

/// Linha do resumo ("Itens", "Taxa de serviço 10%"...). Valores do servidor
/// na mesa; no balcão, o total do carrinho.
typedef ReceiveSummaryLine = ({String label, String value});

/// Um pagamento: os já feitos (resumo) e os desta operação ("Conta paga").
class ReceivedPayment {
  const ReceivedPayment({required this.label, required this.amount, this.charged = false, this.removable = false});
  final String label;
  final double amount;

  /// Cobrado na maquininha (no balcão não pode mais ser retirado).
  final bool charged;

  /// Parte do balcão ainda não cobrada: pode ser retirada da lista.
  final bool removable;
}

enum ReceiveOutcomeKind {
  /// Nada mudou: a mensagem está em [ReceiveController.error].
  failed,

  /// Recebeu e ainda falta: a tela continua, com o novo restante.
  partial,

  /// Quitou (mesa/comanda) ou registrou a venda (balcão).
  done,

  /// Pix online: a tela abre o QR do servidor para [ReceiveOutcome.amount] e
  /// avisa o controlador com `TableReceiveController.pixConfirmed`.
  pix,

  /// A maquininha cobrou mas o registro falhou, ou não respondeu. A tela
  /// mostra o aviso de sempre e volta para a mesa. Está em
  /// [ReceiveOutcome.charge].
  unconfirmed,
}

class ReceiveOutcome {
  const ReceiveOutcome(this.kind, {this.amount = 0, this.label = '', this.charge});
  final ReceiveOutcomeKind kind;
  final double amount;
  final String label;
  final ChargeOutcome? charge;
}

/// Estado comum do recebimento. Um por abertura da tela.
abstract class ReceiveController extends ChangeNotifier {
  ReceiveController({required this.terminal});

  final Terminal terminal;

  /// Total, pago e restante. Na mesa e na comanda vêm do servidor; no balcão
  /// são o carrinho e a soma das partes já lançadas.
  double get total;
  double get paid;
  double get remaining;

  /// "Itens", "Taxa de serviço 10%"... na ordem da tela.
  List<ReceiveSummaryLine> get summary;

  /// Pagamentos já feitos, para o resumo. Lista vazia com [paid] maior que
  /// zero = o servidor não detalhou: a tela mostra só "Pago".
  List<ReceivedPayment> get paidLines;

  List<ReceiveMethod> get methods;

  /// Pagamentos DESTA operação (a lista da tela "Conta paga").
  final List<ReceivedPayment> received = [];

  String? _selectedId;
  bool busy = false;

  /// Esperando o app de pagamento da maquininha.
  bool onTerminal = false;

  /// Valor da cobrança em curso na maquininha.
  double terminalAmount = 0;
  String? error;

  /// O que está acontecendo ("Registrando a venda…").
  String? status;
  bool _disposed = false;

  /// A forma escolhida; antes de escolher, a padrão de cada fluxo.
  ReceiveMethod get selected;

  @protected
  String? get selectedId => _selectedId;

  void select(ReceiveMethod method) {
    if (busy) return;
    _selectedId = method.id;
    error = null;
    notifyListeners();
  }

  /// Esta forma abre o app de pagamento da maquininha?
  bool chargesOnTerminal(ReceiveMethod m) => !m.isOnlinePix && terminalTypeFor(m.method) != null && terminal.canCharge;

  double get receivedTotal => round2(received.fold(0, (a, p) => a + p.amount));

  /// Quanto do total já está pago, de 0 a 1 (barra de progresso).
  double get progress => total <= 0.005 ? 0 : (paid / total).clamp(0, 1).toDouble();

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  /// O operador saiu do app da Stone sem resposta ("Voltei e nada aconteceu").
  Future<void> abandonTerminal() => terminal.abandon();

  @protected
  ReceiveOutcome fail(String message) {
    busy = false;
    onTerminal = false;
    status = null;
    error = message;
    notifyListeners();
    return const ReceiveOutcome(ReceiveOutcomeKind.failed);
  }

  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Recebimento da conta da MESA (`kind: session`) ou de uma COMANDA
/// (`kind: comanda`). Cada pagamento vai ao servidor na hora; o restante é o
/// que o servidor devolve.
class TableReceiveController extends ReceiveController {
  TableReceiveController({
    required this.kind,
    required this.targetId,
    required this.label,
    required this.session,
    required this.methodsStore,
    required this.ledger,
    required super.terminal,
    Comanda? comanda,
  }) : initialComanda = comanda {
    session.addListener(changed);
    methodsStore.addListener(changed);
    ledger.addListener(changed);
    methodsStore.load();
    loadServerPayments();
  }

  /// `session` | `comanda`.
  final String kind;
  final String targetId;

  /// "Mesa 7" / "Comanda Maria": vai para os pagamentos pendentes da
  /// maquininha e para o título do Pix.
  final String label;

  final SessionStore session;
  final PaymentMethodsStore methodsStore;
  final TefLedger ledger;

  /// A comanda como chegou à tela (vale até o servidor devolver a lista).
  final Comanda? initialComanda;

  /// Pagamentos que o servidor lista para a mesa (`GET /sessions/{id}/receipt`).
  /// `null` = não veio lista.
  List<ReceivedPayment>? _serverPayments;

  bool get isComanda => kind == 'comanda';

  SessionDetail? get _s => session.session;
  SessionBill get _bill => _s?.bill ?? const SessionBill();

  /// A comanda como o servidor a devolve agora (ou como chegou à tela).
  Comanda? get comanda => !isComanda
      ? null
      : (session.comandas.where((c) => c.id == targetId).firstOrNull ?? initialComanda);

  @override
  double get total => isComanda ? (comanda?.total ?? 0) : _bill.total;
  @override
  double get paid => isComanda ? (comanda?.paid ?? 0) : _bill.paid;
  @override
  double get remaining => isComanda ? (comanda?.remaining ?? 0) : _bill.remaining;

  /// A mesa (ou a mesa da comanda) foi encerrada no servidor.
  bool get sessionEnded => _s?.status == 'closed' || _s?.status == 'canceled';
  bool get sessionClosed => _s?.status == 'closed';

  /// Nada mais a receber.
  bool get settled => isComanda
      ? (comanda == null || comanda!.status == 'paid' || comanda!.remaining <= 0.005 || sessionEnded)
      : (_bill.settled || sessionEnded);

  @override
  List<ReceiveSummaryLine> get summary {
    if (isComanda) {
      final c = comanda;
      if (c == null) return const [];
      return [
        (label: 'Itens', value: brl(c.itemsSubtotal)),
        if (c.couvert != null && c.couvert!.total > 0.005) (label: 'Couvert', value: '+ ${brl(c.couvert!.total)}'),
        if (c.serviceFee > 0.005)
          (label: 'Taxa de serviço ${percent(c.serviceFeePercentage)}%', value: '+ ${brl(c.serviceFee)}'),
      ];
    }
    final b = _bill;
    return [
      (label: 'Itens', value: brl(b.itemsSubtotal)),
      if (b.couvertAmount > 0.005) (label: 'Couvert', value: '+ ${brl(b.couvertAmount)}'),
      if (b.discount > 0.005) (label: 'Desconto', value: '- ${brl(b.discount)}'),
      if (b.serviceFee > 0.005)
        (label: 'Taxa de serviço ${percent(b.serviceFeePercentage)}%', value: '+ ${brl(b.serviceFee)}'),
    ];
  }

  /// Só lista os pagamentos quando a lista do servidor fecha com o "pago" da
  /// conta; senão a tela mostra a linha única "Pago".
  @override
  List<ReceivedPayment> get paidLines {
    final list = _serverPayments;
    if (list == null || list.isEmpty) return const [];
    final sum = list.fold<double>(0, (a, p) => a + p.amount);
    return (sum - paid).abs() < 0.01 ? list : const [];
  }

  /// Lê os pagamentos já feitos na mesa do mesmo payload usado para imprimir
  /// a conta. É só leitura e é opcional: se falhar, fica a linha "Pago".
  Future<void> loadServerPayments() async {
    if (isComanda || _s == null) return;
    try {
      final receipt = await session.fetchReceipt();
      _serverPayments = [
        for (final p in asList(receipt['payments']))
          ReceivedPayment(label: asString(p['label'], 'Pagamento'), amount: asDouble(p['amount'])),
      ];
    } on ApiException {
      _serverPayments = null;
    }
    changed();
  }

  @override
  List<ReceiveMethod> get methods => [
    for (final o in methodsStore.receiveOptions)
      ReceiveMethod(id: o.method, method: o.method, label: o.label, isCash: o.isCash, isOnlinePix: o.isOnlinePix),
  ];

  @override
  ReceiveMethod get selected {
    final options = methods;
    return options.where((o) => o.id == selectedId).firstOrNull ??
        // Padrão: a primeira forma cobrada na maquininha; senão a primeira.
        options.where(chargesOnTerminal).firstOrNull ??
        options.first;
  }

  /// Cobranças da maquininha desta mesa/comanda que ainda não estão
  /// registradas no Mobizweb (não cobrar de novo).
  List<PendingTef> get pendingTef => [
    for (final p in ledger.pending)
      if (p.kind == kind && p.targetId == targetId) p,
  ];

  Future<String?> _pay({required String method, required double amount, double? cashReceived}) => isComanda
      ? session.payComanda(targetId, method: method, amount: amount, cashReceived: cashReceived)
      : session.payTable(method: method, amount: amount, cashReceived: cashReceived);

  ReceiveOutcome _receivedNow(String label, double amount, {bool charged = false}) {
    received.add(ReceivedPayment(label: label, amount: amount, charged: charged));
    busy = false;
    onTerminal = false;
    status = null;
    error = null;
    changed();
    loadServerPayments();
    return ReceiveOutcome(
      settled ? ReceiveOutcomeKind.done : ReceiveOutcomeKind.partial,
      amount: amount,
      label: label,
    );
  }

  /// Registra `amount` na forma escolhida. `cashReceived` é o "Valor
  /// recebido" (só dinheiro). Com Pix online o valor é sempre o restante.
  Future<ReceiveOutcome> receive({required double amount, double? cashReceived}) async {
    if (busy) return const ReceiveOutcome(ReceiveOutcomeKind.failed);
    final option = selected;
    final rest = remaining;
    final value = option.isOnlinePix ? rest : round2(amount);
    if (value <= 0) return fail('Informe o valor.');
    if (!option.isCash && value > rest + 0.01) {
      return fail('O valor não pode passar do restante (${brl(rest)}). Só dinheiro dá troco.');
    }

    // Pix online: QR gerado pelo servidor (a tela abre a janela do QR).
    if (option.isOnlinePix) {
      error = null;
      changed();
      return ReceiveOutcome(ReceiveOutcomeKind.pix, amount: value, label: option.label);
    }

    // Dinheiro: o servidor exige o valor recebido (troco = diferença).
    if (option.isCash) {
      final got = cashReceived ?? 0;
      if (got + 0.005 < value) return fail('O valor recebido é menor que o valor a pagar.');
      return _record(option, value, () => _pay(method: option.method, amount: value, cashReceived: got));
    }

    // Cartão / Pix / voucher na maquininha.
    final type = terminalTypeFor(option.method);
    if (type != null && terminal.canCharge) {
      busy = true;
      onTerminal = true;
      terminalAmount = value;
      error = null;
      changed();
      final outcome = await ledger.chargeAndRecord(
        kind: kind,
        targetId: targetId,
        label: label,
        method: option.method,
        amount: value,
        type: type,
      );
      switch (outcome.status) {
        case ChargeStatus.recorded:
          final id = _s?.id;
          if (id != null) await session.fetch(id, silent: true);
          if (isComanda) await session.loadComandas();
          final cents = outcome.result?.amountCents;
          return _receivedNow(option.label, (cents != null && cents > 0) ? cents / 100 : value, charged: true);
        case ChargeStatus.declined:
          return fail(outcome.message ?? 'Pagamento não concluído na maquininha.');
        case ChargeStatus.approvedNotRecorded:
        case ChargeStatus.unknown:
          busy = false;
          onTerminal = false;
          changed();
          return ReceiveOutcome(ReceiveOutcomeKind.unconfirmed, amount: value, label: option.label, charge: outcome);
      }
    }

    // Demais formas (ou cobrança na maquininha desligada): só registra.
    return _record(option, value, () => _pay(method: option.method, amount: value));
  }

  Future<ReceiveOutcome> _record(ReceiveMethod option, double value, Future<String?> Function() send) async {
    busy = true;
    error = null;
    changed();
    final failure = await send();
    if (failure != null) return fail(failure);
    return _receivedNow(option.label, value);
  }

  /// O Pix online foi pago e registrado pela janela do QR.
  ReceiveOutcome pixConfirmed(double amount, String label) => _receivedNow(label, amount);

  @override
  void dispose() {
    session.removeListener(changed);
    methodsStore.removeListener(changed);
    ledger.removeListener(changed);
    super.dispose();
  }
}

/// Recebimento da VENDA DE BALCÃO: as partes ficam no aparelho (as de cartão
/// já cobradas na maquininha) e a venda só é gravada quando elas cobrem o
/// total (`POST /counter/checkout`, com a chave de idempotência do carrinho).
class CounterReceiveController extends ReceiveController {
  CounterReceiveController({
    required this.saleTotal,
    required this.options,
    required this.parts,
    required this.items,
    required this.cartKey,
    required this.counter,
    required this.ledger,
    required super.terminal,
  });

  final double saleTotal;

  /// Formas do PDV da loja (`GET /counter/context`).
  final List<PaymentMethodOption> options;

  /// Partes já lançadas. A lista é de quem abriu a tela: voltar e reabrir o
  /// recebimento preserva o que já foi cobrado.
  final List<CounterPayment> parts;
  final List<CartItem> items;
  final String cartKey;

  final CounterStore counter;
  final TefLedger ledger;

  /// A venda registrada (tela "Venda recebida").
  CounterSaleResult? sale;
  String? customerName;

  /// As partes com que a venda foi gravada.
  List<CounterPayment> salePayments = const [];

  /// A loja emite nota fiscal: "Venda recebida" oferece "Imprimir nota
  /// fiscal" (a venda é gravada sem nota e vira fiscal só a pedido).
  bool get fiscalAvailable => sale != null && (counter.context?.fiscalActive ?? false);

  /// A NFC-e desta venda, depois de emitida.
  FiscalNote? fiscalNote;
  bool issuingFiscal = false;

  /// Por que a nota não saiu (motivo da SEFAZ ou falha de rede).
  String? fiscalError;

  /// Emite a NFC-e da venda (ou devolve a já emitida: tocar de novo imprime a
  /// MESMA nota, nunca emite outra). `null` = não saiu; ver [fiscalError].
  Future<FiscalNote?> issueFiscal() async {
    final s = sale;
    if (s == null || issuingFiscal) return null;
    final ready = fiscalNote;
    if (ready != null) return ready;
    issuingFiscal = true;
    fiscalError = null;
    changed();
    try {
      fiscalNote = await counter.issueFiscal(s.orderId, idempotencyKey: 'fiscal-${s.orderId}');
    } on ApiException catch (e) {
      fiscalError = e.isTransient
          ? 'Sem resposta do servidor. Verifique a conexão e toque de novo: a nota não é emitida duas vezes.'
          : e.message;
    } finally {
      issuingFiscal = false;
      changed();
    }
    return fiscalNote;
  }

  /// Quanto o servidor gravou a MENOS que a soma do cardápio (positivo =
  /// desconto; negativo = acréscimo). O cardápio do app traz o preço de
  /// cadastro, mas o servidor recalcula a venda com promoções e tabelas de
  /// preço, então os dois totais podem diferir. `0` antes de registrar.
  double get systemDiscount {
    final s = sale;
    return s == null ? 0 : round2(saleTotal - s.total);
  }

  /// Quanto foi cobrado em cartão, Pix ou outra forma sem troco ALÉM do que o
  /// servidor registrou. O servidor limita essas formas ao total da venda e
  /// só o dinheiro vira troco: esta diferença ficou com a loja e precisa
  /// voltar ao cliente.
  double get overcharged {
    final s = sale;
    if (s == null) return 0;
    var left = s.total;
    var over = 0.0;
    for (final p in salePayments) {
      final applied = p.amount < left ? p.amount : left;
      if (p.method != 'cash') over += p.amount - applied;
      left = round2(left - applied);
    }
    return round2(over);
  }

  static const _cashFallback = ReceiveMethod(id: 'cash', method: 'cash', label: 'Dinheiro', isCash: true);

  @override
  double get total => saleTotal;
  @override
  double get paid => round2(parts.fold(0, (a, p) => a + p.amount));
  @override
  double get remaining {
    final r = round2(saleTotal - paid);
    return r > 0 ? r : 0;
  }

  /// As partes já cobrem o total: falta só registrar a venda.
  bool get covered => paid >= saleTotal - 0.005;

  @override
  List<ReceiveSummaryLine> get summary => [(label: 'Itens', value: brl(saleTotal))];

  @override
  List<ReceivedPayment> get paidLines => [
    for (final p in parts) ReceivedPayment(label: p.label, amount: p.amount, charged: p.charged, removable: !p.charged),
  ];

  @override
  List<ReceiveMethod> get methods => [
    for (final m in options) ReceiveMethod(id: m.code, method: m.method, label: m.name, isCash: m.isCash),
  ];

  @override
  ReceiveMethod get selected {
    final list = methods;
    final id = selectedId ?? options.where((m) => m.isDefault).firstOrNull?.code ?? options.firstOrNull?.code;
    return list.where((m) => m.id == id).firstOrNull ?? _cashFallback;
  }

  /// Troco se `amount` for lançado agora (só dinheiro passa do total).
  double changeFor(double amount) {
    final after = round2(paid + round2(amount));
    return selected.isCash && after > saleTotal ? round2(after - saleTotal) : 0;
  }

  /// Tira da lista uma parte ainda não cobrada.
  void removePart(int index) {
    if (busy || index < 0 || index >= parts.length || parts[index].charged) return;
    parts.removeAt(index);
    error = null;
    changed();
  }

  /// Lança `amount` na forma escolhida (cartão e Pix são cobrados AGORA na
  /// maquininha). Se ainda faltar, continua na tela; quando as partes cobrem
  /// o total, registra a venda.
  Future<ReceiveOutcome> receive({required double amount, String? customer}) async {
    if (busy) return const ReceiveOutcome(ReceiveOutcomeKind.failed);
    final name = customer?.trim() ?? '';
    customerName = name.isEmpty ? null : name;
    if (covered) return _checkout();

    final value = round2(amount);
    final m = selected;
    if (value <= 0) return fail('Informe o valor.');
    if (!m.isCash && value > remaining + 0.005) return fail('Só dinheiro pode passar do valor (troco).');

    busy = true;
    error = null;
    changed();
    var charged = value;
    final type = terminalTypeFor(m.method);
    if (type != null && terminal.canCharge) {
      onTerminal = true;
      terminalAmount = value;
      changed();
      final r = await ledger.chargeOnly(label: 'Balcão · ${m.label}', method: m.method, amount: value, type: type);
      onTerminal = false;
      if (!r.result.approved) {
        return fail(
          r.result.code == 'abandoned'
              ? 'Sem resposta da maquininha. Confira no app da Stone se a cobrança foi aprovada antes de cobrar de '
                    'novo. Ela ficou em Configurações › Pagamentos pendentes.'
              : r.result.failureMessage,
        );
      }
      final cents = r.result.amountCents;
      if (cents != null && cents > 0) charged = cents / 100;
      parts.add(CounterPayment(method: m.method, label: m.label, amount: charged, atk: r.entry?.atk, nsu: r.entry?.nsu));
    } else {
      parts.add(CounterPayment(method: m.method, label: m.label, amount: value));
    }
    received.add(ReceivedPayment(label: m.label, amount: charged));

    if (!covered) {
      busy = false;
      changed();
      return ReceiveOutcome(ReceiveOutcomeKind.partial, amount: charged, label: m.label);
    }
    return _checkout();
  }

  Future<ReceiveOutcome> _checkout() async {
    busy = true;
    error = null;
    status = 'Registrando a venda…';
    changed();
    final payments = List<CounterPayment>.of(parts);
    try {
      final result = await counter.checkout(items, payments, customerName: customerName, idempotencyKey: cartKey);
      sale = result;
      salePayments = payments;
      busy = false;
      status = null;
      changed();
      return ReceiveOutcome(ReceiveOutcomeKind.done, amount: result.total);
    } on ApiException catch (e) {
      return fail(
        e.isTransient
            ? 'Sem resposta do servidor. Verifique a conexão e toque em Registrar venda de novo (não duplica a venda).'
            : e.message,
      );
    }
  }
}
