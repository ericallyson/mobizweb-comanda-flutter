import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../stores/counter.dart';
import '../../stores/order_draft.dart';
import '../../stores/payments.dart';
import '../kit.dart';
import '../order_widgets.dart';
import '../printing.dart';
import 'menu_screen.dart';

/// Venda de balcão (5.7 do plano): o mesmo Cardápio da mesa, a tela "Venda de
/// balcão" para conferir os itens e o recebimento numa tacada só. 100%
/// online; a chave de idempotência por carrinho impede venda duplicada quando
/// a resposta se perde.
///
/// É a tela que a aba "Balcão" abre. O recebimento ainda é a janela atual
/// ([_CheckoutSheet]); a tela nova de "Receber venda" entra depois.
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> with StoreRebuild {
  /// Itens da venda. A chave de idempotência da venda é a do carrinho.
  final _cart = OrderCart();

  /// Parcelas já lançadas no recebimento (as de cartão já foram cobradas).
  final _parts = <CounterPayment>[];
  CounterSaleResult? _lastSale;

  static const _chargedLock = 'Há pagamento já cobrado nesta venda: conclua o recebimento antes de mudar os itens.';

  @override
  void initState() {
    super.initState();
    app.counter.addListener(rebuild);
    _cart.addListener(rebuild);
    app.counter.fetchContext();
  }

  @override
  void dispose() {
    app.counter.removeListener(rebuild);
    _cart.removeListener(rebuild);
    _cart.dispose();
    super.dispose();
  }

  double get _total => round2(_cart.total);
  bool get _hasCharged => _parts.any((p) => p.charged);

  /// Com pagamento já cobrado na maquininha os itens não mudam mais.
  void _syncLock() => _cart.lockReason = _hasCharged ? _chargedLock : null;

  /// "Ver venda": a tela de conferência. Com pagamento já cobrado, vai direto
  /// concluir o recebimento.
  Future<void> _openSale() async {
    if (_hasCharged) {
      await _checkout();
      return;
    }
    FocusScope.of(context).unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => CounterSaleScreen(cart: _cart, onReceive: _checkout)),
    );
  }

  /// Abre o recebimento. Devolve `true` quando a venda foi registrada.
  Future<bool> _checkout() async {
    if (_cart.isEmpty) return false;
    if (_cart.items.any((i) => app.menu.isUnavailable(i.product.id))) {
      toast(context, 'Há item indisponível na venda. Remova antes de receber.', error: true);
      return false;
    }
    final items = _cart.items;
    final result = await showSheet<_CheckoutDone>(
      context,
      (_) => _CheckoutSheet(
        total: _total,
        methods: app.counter.context?.methods ?? const [],
        parts: _parts,
        items: items,
        cartKey: _cart.key,
      ),
      dismissible: false,
    );
    if (!mounted) return false;
    _syncLock();
    setState(() {});
    if (result == null) return false;

    // Venda gravada: as transações da maquininha deixam de estar pendentes.
    await app.ledger.settle(result.payments.map((p) => p.atk).whereType<String>());
    if (!mounted) return true;
    _parts.clear();
    _cart.commit();
    setState(() => _lastSale = result.sale);
    if (app.settings.printCounter && app.terminal.canPrint) {
      // Sem `await`: a tela "Venda de balcão" fecha enquanto o comprovante imprime.
      unawaited(
        printCounterSale(
          context,
          sale: result.sale,
          items: items,
          payments: [for (final p in result.payments) (label: p.label, amount: p.amount)],
          customerName: result.customerName,
        ),
      );
    }
    return true;
  }

  Future<void> _back() async {
    if (_cart.isEmpty || _lastSale != null) {
      Navigator.pop(context);
      return;
    }
    final n = _cart.count;
    final ok = await confirm(
      context,
      title: 'Abandonar a venda?',
      message: _hasCharged
          ? 'ATENÇÃO: há pagamento já cobrado na maquininha nesta venda. Ao abandonar, estorne-o em '
                'Configurações › Pagamentos pendentes.'
          : 'A venda atual será abandonada e ${n == 1 ? 'o item do carrinho será descartado' : 'os $n itens do carrinho serão descartados'}.',
      confirmLabel: 'Abandonar',
      cancelLabel: 'Continuar venda',
      danger: true,
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final counter = app.counter;
    final ctx = counter.context;
    final sale = _lastSale;
    final store = app.auth.store?.name ?? '';

    final Widget body;
    if (counter.loading && ctx == null) {
      body = const StateView(text: 'Carregando...');
    } else if (ctx == null) {
      body = StateView(
        icon: Icons.wifi_off,
        text: counter.error ?? 'Não foi possível carregar o balcão.',
        error: true,
        onAction: counter.fetchContext,
      );
    } else if (!ctx.enabled) {
      body = const StateView(
        icon: Icons.lock_outline,
        text: 'A venda de balcão pelo app não está habilitada para esta loja.',
        detail: 'Peça ao administrador para ativar em Configurações da loja → Mesas.',
      );
    } else if (!ctx.canSell) {
      body = const StateView(icon: Icons.lock_outline, text: 'Seu usuário não tem permissão para vender no balcão.');
    } else if (sale != null) {
      body = _saleDone(sale);
    } else {
      // Vendendo: o mesmo cardápio da mesa, no canal do balcão.
      return MenuScreen(
        cart: _cart,
        title: 'Balcão',
        subtitle: ['Venda de balcão', if (store.isNotEmpty) store].join(' · '),
        channel: 'pos',
        actions: [if (ctx.cashOpen) const Pill('Caixa aberto', bg: C.greenSoft, fg: C.greenText, size: 11)],
        primaryLabel: _hasCharged ? 'Concluir recebimento' : 'Ver venda',
        onPrimary: _openSale,
        onCancel: _back,
      );
    }

    return PopScope(
      canPop: _cart.isEmpty || _lastSale != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(
          children: [
            AppHeader(title: 'Balcão', subtitle: store.isEmpty ? null : store, onBack: _back),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _saleDone(CounterSaleResult sale) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: C.greenSoft, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 34, color: C.green),
          ),
          const SizedBox(height: 12),
          Text(
            sale.number == null ? 'Venda concluída' : 'Venda #${sale.number} concluída',
            textAlign: TextAlign.center,
            style: T.s(21, w: T.bold, c: C.ink, h: 1.25),
          ),
          const SizedBox(height: 4),
          Text(brl(sale.total), style: T.num(24)),
          if (sale.changeAmount > 0.005)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Troco: ${brl(sale.changeAmount)}', style: T.num(14, w: T.semibold, c: C.orangeText)),
            ),
          if (sale.requiresOperatorDecision)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Note(
                'NFC-e rejeitada. Resolva a emissão pelo PDV web. ${sale.blockReason ?? ''}'.trim(),
                kind: NoteKind.error,
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: 240,
            child: Btn('Nova venda de balcão', kind: BtnKind.magenta, onTap: () => setState(() => _lastSale = null)),
          ),
        ],
      ),
    ),
  );
}

/// "Venda de balcão": a lista dos itens com −/+ e o total, "+ Itens" (volta
/// ao cardápio) e "Receber".
class CounterSaleScreen extends StatefulWidget {
  const CounterSaleScreen({super.key, required this.cart, required this.onReceive});
  final OrderCart cart;

  /// Abre o recebimento. Devolve `true` quando a venda foi registrada (a tela
  /// fecha e o balcão mostra "Venda concluída").
  final Future<bool> Function() onReceive;

  @override
  State<CounterSaleScreen> createState() => _CounterSaleScreenState();
}

class _CounterSaleScreenState extends State<CounterSaleScreen> with StoreRebuild {
  bool _receiving = false;

  OrderCart get cart => widget.cart;

  @override
  void initState() {
    super.initState();
    cart.addListener(rebuild);
    app.menu.addListener(rebuild);
    app.api.online.addListener(rebuild);
  }

  @override
  void dispose() {
    cart.removeListener(rebuild);
    app.menu.removeListener(rebuild);
    app.api.online.removeListener(rebuild);
    super.dispose();
  }

  Future<void> _receive() async {
    if (_receiving) return;
    setState(() => _receiving = true);
    final sold = await widget.onReceive();
    if (!mounted) return;
    setState(() => _receiving = false);
    if (sold) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final waiter = app.auth.user?.name.trim() ?? '';
    final store = app.auth.store?.name ?? '';
    final unavailable = cart.items.any((i) => app.menu.isUnavailable(i.product.id));
    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          AppHeader(
            title: 'Venda de balcão',
            subtitle: [if (store.isNotEmpty) store, if (waiter.isNotEmpty) waiter].join(' · '),
            onBack: () => Navigator.pop(context),
          ),
          if (!app.api.online.value) const Note('Sem conexão com o servidor.', radius: 0),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (cart.locked) ...[Note(cart.lockReason!), const SizedBox(height: 12)],
                if (unavailable) ...[
                  const Note('O cardápio mudou: há item indisponível na venda. Remova antes de receber.'),
                  const SizedBox(height: 12),
                ],
                SectionLabel('Itens da venda', trailing: Tag(itemsCountLabel(cart.count))),
                CardBox(
                  padding: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: cart.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('Nenhum item na venda.', style: T.body(c: C.sub)),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (i, item) in cart.items.indexed)
                                CartLine(
                                  key: ValueKey(item.localId),
                                  item: item,
                                  cart: cart,
                                  last: i == cart.items.length - 1,
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                CardBox(
                  padding: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text('Total', style: T.s(16, w: T.bold, c: C.ink, h: 1.3))),
                        Text(brl(round2(cart.total)), style: T.num(16)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomBar.duo(
        Btn('+ Itens', kind: BtnKind.green, onTap: () => Navigator.pop(context)),
        CountBtn(
          label: cart.locked ? 'Concluir recebimento' : 'Receber',
          total: round2(cart.total),
          onTap: cart.isEmpty || _receiving ? null : _receive,
        ),
      ),
    );
  }
}

typedef _CheckoutDone = ({CounterSaleResult sale, List<CounterPayment> payments, String? customerName});

/// Recebimento da venda de balcão, com pagamento dividido em formas.
/// Espelha `CounterCheckoutModal.vue`; cartão/Pix passam pela maquininha.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.total,
    required this.methods,
    required this.parts,
    required this.items,
    required this.cartKey,
  });
  final double total;
  final List<PaymentMethodOption> methods;

  /// Lista da tela de trás: fechar e reabrir a folha preserva o que já foi
  /// cobrado.
  final List<CounterPayment> parts;
  final List<CartItem> items;
  final String cartKey;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late String _code =
      widget.methods.where((m) => m.isDefault).firstOrNull?.code ?? widget.methods.firstOrNull?.code ?? 'cash';
  late final _amount = TextEditingController(text: decimalInput(_remaining));
  final _customer = TextEditingController();
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _customer.dispose();
    super.dispose();
  }

  PaymentMethodOption get _method =>
      widget.methods.where((m) => m.code == _code).firstOrNull ??
      const PaymentMethodOption(code: 'cash', name: 'Dinheiro', method: 'cash', isCash: true);

  double get _partsTotal => round2(widget.parts.fold(0, (a, p) => a + p.amount));
  double get _remaining {
    final r = round2(widget.total - _partsTotal);
    return r > 0 ? r : 0;
  }

  double get _current => round2(parseDecimal(_amount.text));
  double get _paid => round2(_partsTotal + _current);
  double get _change => _method.isCash && _paid > widget.total ? round2(_paid - widget.total) : 0;
  bool get _onTerminal => terminalTypeFor(_method.method) != null && app.terminal.canCharge;

  /// Lança o valor atual como parcela. Cartão/Pix é cobrado AGORA na
  /// maquininha; só entra na lista se aprovado. Devolve `false` se não entrou.
  Future<bool> _addCurrent() async {
    final amount = _current;
    final m = _method;
    if (amount <= 0) return true;
    if (!m.isCash && amount > _remaining + 0.005) {
      setState(() => _error = 'Só dinheiro pode passar do valor (troco).');
      return false;
    }
    final type = terminalTypeFor(m.method);
    if (type != null && app.terminal.canCharge) {
      setState(() => _status = 'Aguardando a maquininha…');
      final r = await app.ledger.chargeOnly(label: 'Balcão · ${m.name}', method: m.method, amount: amount, type: type);
      if (!mounted) return false;
      setState(() => _status = null);
      if (!r.result.approved) {
        setState(() => _error = r.result.failureMessage);
        return false;
      }
      final cents = r.result.amountCents;
      widget.parts.add(
        CounterPayment(
          method: m.method,
          label: m.name,
          amount: (cents != null && cents > 0) ? cents / 100 : amount,
          atk: r.entry?.atk,
          nsu: r.entry?.nsu,
        ),
      );
    } else {
      widget.parts.add(CounterPayment(method: m.method, label: m.name, amount: amount));
    }
    _amount.text = decimalInput(_remaining);
    return true;
  }

  Future<void> _addPart() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _addCurrent();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (_paid < widget.total - 0.005) {
      setState(() => _error = 'O valor recebido não cobre o total da venda.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_current > 0 && !await _addCurrent()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    if (_partsTotal < widget.total - 0.005) {
      setState(() {
        _busy = false;
        _error = 'Falta receber ${brl(_remaining)}.';
      });
      return;
    }
    setState(() => _status = 'Registrando a venda…');
    final payments = List<CounterPayment>.of(widget.parts);
    final customer = _customer.text.trim();
    try {
      final sale = await app.counter.checkout(
        widget.items,
        payments,
        customerName: customer.isEmpty ? null : customer,
        idempotencyKey: widget.cartKey,
      );
      if (mounted) {
        Navigator.pop<_CheckoutDone>(context, (
          sale: sale,
          payments: payments,
          customerName: customer.isEmpty ? null : customer,
        ));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = e.isTransient
            ? 'Sem resposta do servidor. Verifique a conexão e toque em Receber de novo (não duplica a venda).'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    final covered = _partsTotal >= widget.total - 0.005;
    return SheetBody(
      title: 'Receber venda',
      children: [
        bigMoney(widget.total, size: 22),
        const SizedBox(height: 12),
        for (var i = 0; i < parts.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: C.zinc50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${parts[i].label}${parts[i].charged ? ' · cobrado' : ''}',
                    style: T.sm(c: C.zinc700),
                  ),
                ),
                Text(brl(parts[i].amount), style: T.sm(w: T.semibold)),
                const SizedBox(width: 8),
                if (parts[i].charged)
                  const Icon(Icons.lock_outline, size: 16, color: C.emerald600)
                else
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () => setState(() {
                            parts.removeAt(i);
                            _amount.text = decimalInput(_remaining);
                          }),
                    child: const Icon(Icons.close, size: 18, color: C.zinc400),
                  ),
              ],
            ),
          ),
        if (!covered) ...[
          const SizedBox(height: 6),
          Text('FORMA DE PAGAMENTO', style: T.label),
          const SizedBox(height: 6),
          ColGrid(
            cols: 3,
            children: [
              for (final m in widget.methods)
                Choice(m.name, selected: m.code == _code, onTap: _busy ? null : () => setState(() {
                  _code = m.code;
                  _error = null;
                })),
            ],
          ),
          if (widget.methods.isEmpty) Text('Nenhuma forma de pagamento ativa no PDV desta loja.', style: T.xs(c: C.amber600)),
          const SizedBox(height: 12),
          MoneyField(
            label: parts.isEmpty ? 'Valor' : 'Valor (restante ${brl(_remaining)})',
            controller: _amount,
            enabled: !_busy,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_current > 0 && _current < _remaining - 0.005)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Btn(
                _onTerminal ? '+ Cobrar esta parte e escolher outra forma' : '+ Adicionar como parcial e escolher outra forma',
                kind: BtnKind.outline,
                dense: true,
                onTap: _busy ? null : _addPart,
              ),
            ),
          if (_change > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Troco: ${brl(_change)}', style: T.sm(w: T.semibold, c: C.amber700)),
            ),
          const SizedBox(height: 12),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Note('Valor coberto. Toque em Receber para registrar a venda.', kind: NoteKind.info),
          ),
        Field(label: 'Cliente (opcional)', controller: _customer, hint: 'Nome do cliente', maxLength: 100),
        const SizedBox(height: 10),
        if (_status != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Note(_status!, kind: NoteKind.info)),
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(
          _busy ? 'Recebendo...' : (_onTerminal && !covered ? 'Cobrar e receber' : 'Receber'),
          loading: _busy,
          onTap: (covered || _paid >= widget.total - 0.005) ? _confirm : null,
        ),
      ),
    );
  }
}
