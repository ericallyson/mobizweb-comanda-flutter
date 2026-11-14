import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../print/receipt.dart';
import '../../stores/counter.dart';
import '../../stores/payments.dart';
import '../../stores/receive.dart';
import '../kit.dart';
import '../printing.dart';
import '../sheets/pix_sheet.dart';

/// O que [ReceiveScreen] devolve ao fechar.
class ReceiveResult {
  const ReceiveResult({this.received = false, this.done = false});

  /// Algum pagamento foi registrado nesta abertura da tela.
  final bool received;

  /// A conta foi quitada (mesa, comanda) ou a venda foi registrada (balcão).
  final bool done;
}

/// O que a venda de balcão entrega para a tela de recebimento.
class CounterSaleRequest {
  const CounterSaleRequest({
    required this.total,
    required this.methods,
    required this.parts,
    required this.items,
    required this.cartKey,
    required this.onSold,
  });
  final double total;
  final List<PaymentMethodOption> methods;

  /// Lista de quem chama: voltar e reabrir o recebimento preserva as partes
  /// já cobradas na maquininha.
  final List<CounterPayment> parts;
  final List<CartItem> items;
  final String cartKey;

  /// Chamado UMA vez, assim que a venda é registrada (antes da tela "Venda
  /// recebida"): quem chama dá baixa nas cobranças, limpa o carrinho e
  /// imprime o comprovante.
  final Future<void> Function(CounterSaleResult sale, List<CounterPayment> payments, String? customerName) onSold;
}

/// Ícone da forma de pagamento pelo método canônico.
IconData paymentIcon(ReceiveMethod m) {
  if (m.isOnlinePix) return Icons.qr_code_2;
  return switch (m.method) {
    'cash' => Icons.payments_outlined,
    'pix' || 'mp_pix' || 'mt_pix' => Icons.pix,
    'debit_card' => Icons.payment,
    'credit_card' => Icons.credit_card,
    'voucher' => Icons.confirmation_number_outlined,
    'courtesy' => Icons.card_giftcard,
    'credit_account' => Icons.event_note_outlined,
    'prepaid_wallet' => Icons.account_balance_wallet_outlined,
    _ => Icons.more_horiz,
  };
}

/// Receber conta (mesa e comanda) e Receber venda (balcão): seção 5.6 do
/// layout novo. No lugar das antigas janelas `ReceiveSheet` e `_CheckoutSheet`.
///
/// A tela só desenha: as regras estão em `lib/stores/receive.dart`
/// ([TableReceiveController] e [CounterReceiveController]). Valor menor que o
/// restante registra e continua aqui, com o novo restante; ao quitar, a
/// própria tela vira "Conta paga" / "Venda recebida".
class ReceiveScreen extends StatefulWidget {
  /// Conta da mesa aberta em `app.session`.
  const ReceiveScreen.table({super.key}) : comanda = null, counter = null;

  /// Conta de uma comanda da mesa aberta em `app.session`.
  const ReceiveScreen.comanda({super.key, required Comanda this.comanda}) : counter = null;

  /// Venda de balcão.
  const ReceiveScreen.counter({super.key, required CounterSaleRequest this.counter}) : comanda = null;

  final Comanda? comanda;
  final CounterSaleRequest? counter;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late final ReceiveController c;
  late final TextEditingController _amount;
  late final TextEditingController _cash;
  final _customer = TextEditingController();

  /// O operador mexeu no "Valor recebido": ele deixa de acompanhar o "Valor".
  bool _cashEdited = false;
  bool _closing = false;
  bool _printing = false;
  bool _printingSale = false;

  /// Troco do último pagamento em dinheiro (aparece em "Conta paga").
  double _lastChange = 0;

  TableReceiveController? get _table => c is TableReceiveController ? c as TableReceiveController : null;
  CounterReceiveController? get _counter => c is CounterReceiveController ? c as CounterReceiveController : null;

  @override
  void initState() {
    super.initState();
    final sale = widget.counter;
    final session = app.session.session;
    if (sale != null) {
      c = CounterReceiveController(
        saleTotal: sale.total,
        options: sale.methods,
        parts: sale.parts,
        items: sale.items,
        cartKey: sale.cartKey,
        counter: app.counter,
        ledger: app.ledger,
        terminal: app.terminal,
      );
    } else {
      final comanda = widget.comanda;
      c = TableReceiveController(
        kind: comanda == null ? 'session' : 'comanda',
        targetId: comanda?.id ?? session?.id ?? '',
        label: comanda == null ? (session?.title ?? 'Mesa') : 'Comanda ${comanda.label}',
        session: app.session,
        methodsStore: app.methods,
        ledger: app.ledger,
        terminal: app.terminal,
        comanda: comanda,
      );
    }
    _amount = TextEditingController(text: decimalInput(c.remaining));
    _cash = TextEditingController(text: decimalInput(c.remaining));
    c.addListener(_changed);
    app.api.online.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    app.api.online.removeListener(_changed);
    c.dispose();
    _amount.dispose();
    _cash.dispose();
    _customer.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _isCounter => widget.counter != null;

  /// Quitou nesta abertura da tela: mostra "Conta paga" / "Venda recebida".
  bool get _done => _isCounter ? _counter!.sale != null : (_table!.received.isNotEmpty && _table!.settled);

  double get _value => round2(parseDecimal(_amount.text));

  /// Troco do dinheiro, como o app já calculava: mesa = recebido menos valor;
  /// balcão = o que passa do total.
  double get _change {
    if (!c.selected.isCash) return 0;
    if (_isCounter) return _counter!.changeFor(_value);
    final diff = parseDecimal(_cash.text) - _value;
    return diff > 0 ? round2(diff) : 0;
  }

  void _resetFields() {
    _amount.text = decimalInput(c.remaining);
    _cash.text = decimalInput(c.remaining);
    _cashEdited = false;
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (c.busy) return;
    FocusScope.of(context).unfocus();
    final counter = _counter;
    if (counter != null) {
      final partsBefore = counter.parts.length;
      final outcome = await counter.receive(amount: _value, customer: _customer.text);
      if (!mounted) return;
      switch (outcome.kind) {
        case ReceiveOutcomeKind.partial:
          setState(_resetFields);
          toast(context, '${brl(outcome.amount)} recebido em ${outcome.label}');
        case ReceiveOutcomeKind.done:
          await widget.counter!.onSold(counter.sale!, counter.salePayments, counter.customerName);
        case ReceiveOutcomeKind.failed:
          // Uma parte pode ter entrado antes de a venda falhar ao registrar.
          if (counter.parts.length != partsBefore) setState(_resetFields);
        case ReceiveOutcomeKind.pix:
        case ReceiveOutcomeKind.unconfirmed:
          break;
      }
      return;
    }
    final table = _table!;
    final change = _change;
    final outcome = await table.receive(amount: _value, cashReceived: parseDecimal(_cash.text));
    if (!mounted) return;
    await _afterTable(outcome, change: change);
  }

  Future<void> _afterTable(ReceiveOutcome outcome, {double change = 0}) async {
    final table = _table!;
    switch (outcome.kind) {
      case ReceiveOutcomeKind.failed:
        break;
      case ReceiveOutcomeKind.pix:
        // Pix online: QR gerado pelo servidor.
        final paid = await showSheet<bool>(
          context,
          (_) => PixSheet(kind: table.kind, targetId: table.targetId, label: table.label, amount: outcome.amount),
          dismissible: false,
        );
        if (paid == true && mounted) await _afterTable(table.pixConfirmed(outcome.amount, outcome.label));
      case ReceiveOutcomeKind.partial:
        app.tables.fetch();
        setState(_resetFields);
        toast(
          context,
          '${brl(outcome.amount)} recebido em ${outcome.label}${change > 0.005 ? '. Troco: ${brl(change)}' : ''}',
        );
      case ReceiveOutcomeKind.done:
        app.tables.fetch();
        if (change > 0.005) setState(() => _lastChange = change);
      case ReceiveOutcomeKind.unconfirmed:
        final approved = outcome.charge?.status == ChargeStatus.approvedNotRecorded;
        await confirm(
          context,
          title: approved ? 'Cobrado, mas não registrado' : 'Sem resposta da maquininha',
          message: approved
              ? 'O cartão foi cobrado, mas o Mobizweb não confirmou o registro (${outcome.charge?.message}). '
                    'O pagamento ficou guardado em Configurações › Pagamentos pendentes e será reenviado. '
                    'NÃO cobre de novo.'
              : 'Confira no app da Stone se a cobrança foi aprovada antes de cobrar de novo. '
                    'Ela ficou em Configurações › Pagamentos pendentes.',
          confirmLabel: 'Entendi',
          cancelLabel: 'Fechar',
        );
        if (mounted) Navigator.pop(context, const ReceiveResult(received: true));
    }
  }

  void _back() {
    if (c.busy) return;
    Navigator.pop(context, ReceiveResult(received: c.received.isNotEmpty));
  }

  void _finish() => Navigator.pop(context, ReceiveResult(received: true, done: true));

  /// Fechamento explícito: conta quitada e mesa ainda aberta no servidor.
  Future<void> _closeSession() async {
    if (_closing) return;
    setState(() => _closing = true);
    final error = await app.session.closeSession();
    if (!mounted) return;
    setState(() => _closing = false);
    app.tables.fetch();
    if (error != null) {
      toast(context, error, error: true);
    } else if (app.session.session?.status == 'closed') {
      toast(context, 'Mesa fechada.');
    }
  }

  Future<void> _printReceipt() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final receipt = await app.session.fetchReceipt();
      final error = await app.terminal.printLines(
        billReceipt(receipt, guestCount: app.session.session?.guestCount, title: 'COMPROVANTE'),
      );
      if (error != null && mounted) toast(context, 'Impressão: $error', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, 'Não foi possível montar o comprovante: ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// "Imprimir nota": emite a NFC-e da venda (uma vez só) e imprime o DANFE
  /// na maquininha. Tocar de novo reimprime a mesma nota.
  Future<void> _printFiscal() async {
    final counter = _counter;
    if (_printing || counter == null) return;
    setState(() => _printing = true);
    final note = await counter.issueFiscal();
    if (note != null && mounted) {
      final error = await app.terminal.printLines(danfeReceipt(note));
      if (error != null && mounted) toast(context, 'Nota emitida, mas não imprimiu: $error', error: true);
    }
    if (mounted) setState(() => _printing = false);
  }

  /// "Imprimir venda": o comprovante comum (não fiscal) da venda de balcão.
  Future<void> _printSale() async {
    final counter = _counter;
    final sale = counter?.sale;
    if (_printingSale || counter == null || sale == null) return;
    setState(() => _printingSale = true);
    await printCounterSale(
      context,
      sale: sale,
      items: counter.items,
      payments: [for (final p in counter.salePayments) (label: p.label, amount: p.amount)],
      customerName: counter.customerName,
    );
    if (mounted) setState(() => _printingSale = false);
  }

  // ── Textos ────────────────────────────────────────────────────────────────

  String get _subtitle {
    final store = app.auth.store?.name ?? '';
    if (_isCounter) return ['Balcão', if (store.isNotEmpty) store].join(' · ');
    final s = app.session.session;
    final guests = s?.guestCount;
    final comanda = widget.comanda;
    return [
      s?.title ?? 'Mesa',
      if (comanda != null) 'Comanda ${comanda.label}',
      // "Conta paga" cita só a mesa, como no protótipo.
      if (comanda == null && !_done && guests != null && guests > 0) guests == 1 ? '1 pessoa' : '$guests pessoas',
    ].join(' · ');
  }

  String get _barLabel {
    final m = c.selected;
    final counter = _counter;
    if (counter != null && counter.covered) return 'Registrar venda ${brl(counter.total)}';
    if (m.isOnlinePix) return 'Gerar Pix de ${brl(c.remaining)}';
    return '${c.chargesOnTerminal(m) ? 'Cobrar' : 'Receber'} ${brl(_value)} em ${m.label}';
  }

  String get _doneButton {
    if (_isCounter) return 'Nova venda de balcão';
    final table = _table!;
    return (table.isComanda && !table.sessionEnded) ? 'Voltar às comandas' : 'Voltar às mesas';
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final done = _done;
    final offline = !app.api.online.value;
    final Widget body;
    final Widget bar;
    if (c.onTerminal) {
      body = _waiting();
      bar = BottomBar(
        children: [Btn('Voltei e nada aconteceu', kind: BtnKind.secondary, onTap: c.abandonTerminal)],
      );
    } else if (done) {
      body = _doneView();
      bar = BottomBar(children: [Btn(_doneButton, kind: BtnKind.navy, onTap: _finish)]);
    } else {
      body = _form(offline);
      final nothing = !_isCounter && c.remaining <= 0.005;
      bar = BottomBar(
        children: [
          Btn(
            c.busy ? (c.status ?? 'Registrando...') : (nothing ? 'Nada a receber' : _barLabel),
            kind: BtnKind.magenta,
            loading: c.busy,
            onTap: nothing || (offline && !_isCounter) ? null : _submit,
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || c.busy) return;
        done ? _finish() : _back();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(
          children: [
            AppHeader(
              title: done
                  ? (_isCounter ? 'Venda recebida' : 'Conta paga')
                  : (_isCounter ? 'Receber venda' : 'Receber conta'),
              subtitle: _subtitle,
              onBack: done || c.onTerminal ? null : _back,
            ),
            if (offline && !done)
              Note(_isCounter ? 'Sem conexão com o servidor.' : 'Recebimento exige conexão.', radius: 0),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: bar,
      ),
    );
  }

  /// "Aguardando a maquininha": o app de pagamento da Stone está na frente.
  Widget _waiting() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: C.navy)),
          const SizedBox(height: 18),
          Text('Aguardando a maquininha…', textAlign: TextAlign.center, style: T.s(17, w: T.bold, c: C.ink, h: 1.3)),
          const SizedBox(height: 6),
          Text(
            'Conclua o pagamento de ${brl(c.terminalAmount)} no app da Stone. Esta tela volta sozinha.',
            textAlign: TextAlign.center,
            style: T.body(c: C.sub),
          ),
        ],
      ),
    ),
  );

  Widget _form(bool offline) {
    final counter = _counter;
    final table = _table;
    final selected = c.selected;
    final covered = counter?.covered ?? false;
    final methods = c.methods;
    final change = _change;
    final pending = table?.pendingTef ?? const <PendingTef>[];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _hero(),
        const SizedBox(height: 12),
        _summary(),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          Note(
            'Há ${pending.length == 1 ? 'uma cobrança' : '${pending.length} cobranças'} da maquininha sem registro nesta '
            'conta (${brl(pending.fold<double>(0, (a, p) => a + p.amount))}). Não cobre de novo: confira em '
            'Configurações › Pagamentos pendentes.',
            center: false,
            radius: 12,
          ),
        ],
        const SizedBox(height: 12),
        if (covered)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Note(
              'Valor coberto. Toque em Registrar venda para concluir.',
              kind: NoteKind.info,
              radius: 12,
            ),
          )
        else ...[
          const SectionLabel('Forma de pagamento'),
          if (methods.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Nenhuma forma de pagamento ativa no PDV desta loja.',
                style: T.s(12, w: T.semibold, c: C.orangeText, h: 1.35),
              ),
            )
          else
            ColGrid(
              cols: 3,
              children: [
                for (final m in methods)
                  _MethodTile(
                    method: m,
                    selected: m.id == selected.id,
                    onTap: c.busy ? null : () => c.select(m),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          if (c.chargesOnTerminal(selected))
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Row(
                children: [
                  const Icon(Icons.contactless_outlined, size: 16, color: C.sub),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      app.terminal.isDemo
                          ? 'Modo demonstração: a cobrança é simulada.'
                          : 'A cobrança abre o app de pagamento da maquininha.',
                      style: T.s(12, c: C.sub, h: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          if (selected.isOnlinePix)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                'O Pix online é gerado para o valor restante inteiro.',
                style: T.s(12, c: C.sub, h: 1.35),
              ),
            )
          else ...[
            _ValueRow(
              label: 'Valor',
              controller: _amount,
              enabled: !c.busy,
              onChanged: (v) {
                if (!_cashEdited) _cash.text = v;
                c.clearError();
                setState(() {});
              },
            ),
            if (selected.isCash && !_isCounter)
              _ValueRow(
                label: 'Valor recebido',
                controller: _cash,
                enabled: !c.busy,
                onChanged: (_) {
                  _cashEdited = true;
                  c.clearError();
                  setState(() {});
                },
              ),
            if (selected.isCash && (!_isCounter || change > 0.005))
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Row(
                  children: [
                    Expanded(child: Text('Troco', style: T.s(13, w: T.semibold, c: C.sub, h: 1.3))),
                    Text(brl(change), style: T.num(14, c: change > 0.005 ? C.orangeText : C.sub)),
                  ],
                ),
              ),
          ],
        ],
        if (_isCounter)
          _ValueRow(
            label: 'Cliente (opcional)',
            controller: _customer,
            enabled: !c.busy,
            money: false,
            hint: 'Nome do cliente',
            width: 170,
            maxLength: 100,
          ),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Note(c.error!, kind: NoteKind.error, radius: 12),
          ),
      ],
    );
  }

  /// Cartão navy: o que falta, a barra de progresso e "pago / total".
  Widget _hero() => HeroCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Valor restante', style: T.s(12, c: C.navySub, h: 1.3)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(brl(c.remaining), maxLines: 1, style: T.num(28, c: C.white, h: 1.2)),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0x2EFFFFFF)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: c.progress,
                  child: const ColoredBox(color: C.mint),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('pago ${brl(c.paid)}', style: T.num(11.5, w: T.medium, c: C.navySub, h: 1.3))),
            Text('total ${brl(c.total)}', style: T.num(11.5, w: T.medium, c: C.navySub, h: 1.3)),
          ],
        ),
      ],
    ),
  );

  /// Itens, taxa de serviço e os pagamentos já feitos.
  Widget _summary() {
    final lines = c.paidLines;
    final counter = _counter;
    Widget row(String label, String value, {Color color = C.ink, Widget? trailing}) => Padding(
      padding: EdgeInsets.symmetric(vertical: trailing == null ? 3 : 0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: T.s(13.5, c: color, h: 1.4))),
          Text(value, style: T.num(13.5, w: T.medium, c: color, h: 1.4)),
          ?trailing,
        ],
      ),
    );
    return CardBox(
      padding: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in c.summary) row(l.label, l.value),
            for (final (i, p) in lines.indexed)
              row(
                'Pagamento ${i + 1} · ${p.label}${p.charged && counter != null ? ' · cobrado' : ''}',
                brl(p.amount),
                color: C.greenText,
                trailing: counter == null
                    ? null
                    : p.removable
                    ? Semantics(
                        button: true,
                        label: 'Remover pagamento ${i + 1}',
                        child: InkResponse(
                          onTap: c.busy
                              ? null
                              : () {
                                  counter.removePart(i);
                                  setState(_resetFields);
                                },
                          radius: 22,
                          child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close, size: 18, color: C.sub)),
                        ),
                      )
                    : const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.lock_outline, size: 16, color: C.greenText),
                      ),
              ),
            if (lines.isEmpty && c.paid > 0.005) row('Pago', brl(c.paid), color: C.greenText),
          ],
        ),
      ),
    );
  }

  Widget _saleLine(String label, String value, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: T.body(w: bold ? T.semibold : FontWeight.w400, c: color ?? C.ink))),
        Text(value, style: T.num(13.5, c: color ?? C.ink)),
      ],
    ),
  );

  /// "Conta paga" / "Venda recebida".
  Widget _doneView() {
    final counter = _counter;
    final table = _table;
    final sale = counter?.sale;
    final payments = counter != null
        ? [for (final p in counter.salePayments) ReceivedPayment(label: p.label, amount: p.amount)]
        : c.received;
    final total = counter != null ? (sale?.total ?? counter.total) : c.receivedTotal;
    final change = counter != null ? (sale?.changeAmount ?? 0) : _lastChange;
    final n = payments.length;
    final p = app.auth.permissions;
    final waitingClose = table != null && !table.isComanda && !table.sessionEnded;
    final canPrint = table != null && !table.isComanda && app.terminal.canPrint && app.settings.printBill;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 26, 10, 8),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: C.greenSoft, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 34, color: Color(0xFF0A9A6A)),
              ),
              const SizedBox(height: 12),
              Text(
                counter != null ? 'Venda recebida!' : 'Conta paga!',
                textAlign: TextAlign.center,
                style: T.s(21, w: T.bold, c: C.ink, h: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                '${brl(total)} ${n == 1 ? 'recebidos em 1 pagamento' : 'recebidos em $n pagamentos'}',
                textAlign: TextAlign.center,
                style: T.body(c: C.sub),
              ),
              if (sale?.number != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Venda #${sale!.number}', style: T.body(c: C.sub)),
                ),
              if (change > 0.005)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Troco: ${brl(change)}', style: T.num(15, c: C.orangeText)),
                ),
            ],
          ),
        ),
        CardBox(
          padding: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, pay) in payments.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      border: i == payments.length - 1 ? null : const Border(bottom: BorderSide(color: C.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Pagamento ${i + 1}', style: T.body(w: T.semibold)),
                              Text(pay.label, style: T.s(12, c: C.sub, h: 1.35)),
                            ],
                          ),
                        ),
                        Text(brl(pay.amount), style: T.num(13.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (counter != null && counter.systemDiscount.abs() > 0.005) ...[
          const SizedBox(height: 12),
          CardBox(
            padding: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _saleLine('Itens pelo preço do cardápio', brl(counter.total)),
                  _saleLine(
                    counter.systemDiscount > 0 ? 'Desconto aplicado pelo sistema' : 'Acréscimo aplicado pelo sistema',
                    '${counter.systemDiscount > 0 ? '-' : '+'} ${brl(counter.systemDiscount.abs())}',
                    color: counter.systemDiscount > 0 ? C.greenText : C.orangeText,
                  ),
                  _saleLine('Total da venda', brl(total), bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Note(
            'O Mobizweb gravou a venda com promoção ou tabela de preço que o cardápio do app não mostra.',
            radius: 12,
            kind: NoteKind.info,
          ),
        ],
        if (counter != null && counter.overcharged > 0.005) ...[
          const SizedBox(height: 12),
          Note(
            'Foram cobrados ${brl(counter.overcharged)} a mais do que o total da venda em cartão ou Pix. '
            'Devolva essa diferença ao cliente.',
            kind: NoteKind.error,
            radius: 12,
          ),
        ],
        if (sale != null && sale.requiresOperatorDecision) ...[
          const SizedBox(height: 12),
          Note(
            'NFC-e rejeitada. Resolva a emissão pelo PDV web. ${sale.blockReason ?? ''}'.trim(),
            kind: NoteKind.error,
            radius: 12,
          ),
        ],
        if (waitingClose) ...[
          const SizedBox(height: 12),
          const Note('Conta quitada. Aguardando fechamento da mesa.', radius: 12),
          const SizedBox(height: 10),
          if (p.closeSession)
            Btn('Fechar mesa', kind: BtnKind.navy, loading: _closing, onTap: _closeSession)
          else
            Text(
              'Seu usuário não tem permissão para fechar a mesa. Chame quem pode concluir.',
              textAlign: TextAlign.center,
              style: T.s(12, c: C.sub, h: 1.35),
            ),
        ],
        if (counter != null && counter.fiscalAvailable) ...[
          const SizedBox(height: 12),
          if (counter.fiscalNote != null) ...[
            Note(
              counter.fiscalNote!.number != null
                  ? 'NFC-e nº ${counter.fiscalNote!.number} emitida para esta venda.'
                  : 'NFC-e emitida para esta venda.',
              kind: NoteKind.info,
              radius: 12,
            ),
            const SizedBox(height: 8),
          ],
          if (counter.fiscalError != null) ...[
            Note(counter.fiscalError!, kind: NoteKind.error, radius: 12),
            const SizedBox(height: 8),
          ],
          // Um cupom ou outro: nada sai sozinho e o operador escolhe. Depois
          // que a nota existe, o comprovante comum deixa de ser oferecido.
          Row(
            children: [
              if (counter.fiscalNote == null) ...[
                Expanded(
                  child: Btn(
                    'Imprimir venda',
                    kind: BtnKind.secondary,
                    icon: Icons.print_outlined,
                    loading: _printingSale,
                    onTap: _printing || counter.issuingFiscal ? null : _printSale,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Btn(
                  'Imprimir nota',
                  kind: BtnKind.secondary,
                  icon: Icons.receipt_long_outlined,
                  loading: _printing || counter.issuingFiscal,
                  onTap: _printingSale ? null : _printFiscal,
                ),
              ),
            ],
          ),
        ],
        if (canPrint) ...[
          const SizedBox(height: 12),
          Btn(
            'Imprimir comprovante',
            kind: BtnKind.secondary,
            icon: Icons.print_outlined,
            loading: _printing,
            onTap: _printReceipt,
          ),
        ],
      ],
    );
  }
}

/// Uma forma de pagamento na grade: ícone e nome; a escolhida fica rosa.
class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.selected, this.onTap});
  final ReceiveMethod method;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? C.magentaText : C.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Tap(
        onTap: onTap,
        color: selected ? C.magentaSoft : C.white,
        border: BorderSide(color: selected ? C.magenta : C.line, width: 1.5),
        radius: 12,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 61),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(paymentIcon(method), size: 20, color: fg),
                const SizedBox(height: 4),
                Text(
                  method.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.s(12, w: T.bold, c: fg, h: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha "rótulo …… campo" em cartão branco (Valor, Valor recebido, Cliente).
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.controller,
    this.onChanged,
    this.enabled = true,
    this.money = true,
    this.hint,
    this.width = 130,
    this.maxLength,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Campo de valor em reais (alinhado à direita, teclado decimal).
  final bool money;
  final String? hint;
  final double width;
  final int? maxLength;

  static final _moneyFormat = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
    decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Expanded(child: Text(label, style: T.s(13, w: T.semibold, c: C.ink, h: 1.3))),
        const SizedBox(width: 10),
        SizedBox(
          width: width,
          // O rótulo ao lado já nomeia o campo para o leitor de tela (os dois
          // caem no mesmo nó de semântica da linha).
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: money ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            textAlign: money ? TextAlign.right : TextAlign.left,
            textCapitalization: money ? TextCapitalization.none : TextCapitalization.words,
            inputFormatters: [
              if (money) ..._moneyFormat,
              if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
            ],
            autocorrect: false,
            onChanged: onChanged,
            style: money ? T.num(16, c: enabled ? C.ink : C.sub) : T.s(14, w: T.medium, c: C.ink),
            decoration: fieldDecoration(hint: hint ?? '0,00', fill: enabled ? C.white : C.bg),
          ),
        ),
      ],
    ),
  );
}
