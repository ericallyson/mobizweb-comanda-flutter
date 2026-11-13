import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/uuid.dart';
import '../../models/models.dart';
import '../../stores/counter.dart';
import '../../stores/payments.dart';
import '../catalog.dart';
import '../kit.dart';
import '../printing.dart';
import '../sheets/session_sheets.dart';
import 'product_screen.dart';

/// Venda de balcão: carrinho + recebimento numa tacada só. Espelha
/// `CounterView.vue`. 100% online; a chave de idempotência por carrinho
/// impede venda duplicada quando a resposta se perde.
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  final _cart = <CartItem>[];

  /// Parcelas já lançadas no recebimento (as de cartão já foram cobradas).
  final _parts = <CounterPayment>[];
  String _cartKey = uuidV7();
  CounterSaleResult? _lastSale;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.counter.addListener(_changed);
    app.counter.fetchContext();
  }

  @override
  void dispose() {
    app.counter.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  double get _total => round2(_cart.fold(0, (a, i) => a + i.total));
  int get _count => _cart.fold(0, (a, i) => a + (i.product.allowFractionalQty ? 1 : i.quantity.round()));
  bool get _hasCharged => _parts.any((p) => p.charged);

  Future<void> _selectProduct(MenuProduct product) async {
    if (_hasCharged) {
      toast(context, 'Há pagamento já cobrado nesta venda: conclua o recebimento antes de mudar os itens.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final item = await Navigator.push<CartItem>(
      context,
      MaterialPageRoute(builder: (_) => ProductScreen(product: product), fullscreenDialog: true),
    );
    if (item != null && mounted) setState(() => _cart.add(item));
  }

  Future<void> _openCart() async {
    if (_hasCharged) {
      await _checkout();
      return;
    }
    final go = await showSheet<bool>(
      context,
      (_) => CartSheet(
        title: 'Venda de balcão',
        cart: _cart,
        onChanged: _changed,
        unavailableText: 'O cardápio mudou: há item indisponível na venda. Remova antes de receber.',
        actionLabel: (total) => 'Receber (${brl(total)})',
        // A folha só valida e fecha; o recebimento abre em seguida.
        onAction: (_) async => _cart.any((i) => app.menu.isUnavailable(i.product.id))
            ? 'Há item indisponível na venda. Remova antes de receber.'
            : null,
      ),
    );
    _changed();
    if (go == true && mounted && _cart.isNotEmpty) await _checkout();
  }

  Future<void> _checkout() async {
    setState(() => _error = null);
    final items = List<CartItem>.of(_cart);
    final result = await showSheet<_CheckoutDone>(
      context,
      (_) => _CheckoutSheet(
        total: _total,
        methods: app.counter.context?.methods ?? const [],
        parts: _parts,
        items: items,
        cartKey: _cartKey,
      ),
      dismissible: false,
    );
    if (!mounted) return;
    setState(() {});
    if (result == null) return;

    // Venda gravada: as transações da maquininha deixam de estar pendentes.
    await app.ledger.settle(result.payments.map((p) => p.atk).whereType<String>());
    if (!mounted) return;
    setState(() {
      _lastSale = result.sale;
      _cart.clear();
      _parts.clear();
      _cartKey = uuidV7();
    });
    if (app.settings.printCounter && app.terminal.canPrint) {
      await printCounterSale(
        context,
        sale: result.sale,
        items: items,
        payments: [for (final p in result.payments) (label: p.label, amount: p.amount)],
        customerName: result.customerName,
      );
    }
  }

  Future<void> _back() async {
    if (_cart.isEmpty || _lastSale != null) {
      Navigator.pop(context);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Abandonar a venda?',
      message: _hasCharged
          ? 'ATENÇÃO: há pagamento já cobrado na maquininha nesta venda. Ao abandonar, estorne-o em '
                'Configurações › Pagamentos pendentes.'
          : 'A venda atual será abandonada e os $_count item(ns) do carrinho serão descartados.',
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

    Widget body;
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
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 56, color: C.emerald500),
              const SizedBox(height: 12),
              Text('Venda #${sale.number ?? '—'} concluída', style: T.base(w: T.bold)),
              const SizedBox(height: 4),
              bigMoney(sale.total, size: 24),
              if (sale.changeAmount > 0.005)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Troco: ${brl(sale.changeAmount)}', style: T.sm(w: T.semibold, c: C.amber700)),
                ),
              if (sale.requiresOperatorDecision)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Note('NFC-e rejeitada — resolva a emissão pelo PDV web. ${sale.blockReason ?? ''}', kind: NoteKind.error),
                ),
              const SizedBox(height: 20),
              SizedBox(width: 220, child: Btn('Nova venda', kind: BtnKind.accent, onTap: () => setState(() => _lastSale = null))),
            ],
          ),
        ),
      );
    } else {
      body = Column(
        children: [
          Expanded(child: CatalogBrowser(channel: 'pos', onSelect: _selectProduct)),
          if (_error != null) Note(_error!, kind: NoteKind.error, radius: 0),
          if (_cart.isNotEmpty)
            Tap(
              onTap: _openCart,
              color: C.secondary500,
              radius: 0,
              splash: Colors.white24,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                    child: Text('$_count', style: T.sm(w: T.bold, c: C.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasCharged ? 'Concluir recebimento (${brl(_total)})' : 'Ver venda (${brl(_total)})',
                      style: T.sm(w: T.semibold, c: C.white),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: C.white),
                ],
              ),
            ),
        ],
      );
    }

    return PopScope(
      canPop: _cart.isEmpty || _lastSale != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: C.zinc50,
        body: Column(
          children: [
            AppHeader(
              title: 'Balcão',
              subtitle: app.auth.store?.name,
              onBack: _back,
              actions: [
                if (ctx?.cashOpen ?? false) const Pill('Caixa aberto', bg: C.emerald100, fg: C.emerald700, size: 11),
              ],
            ),
            Expanded(child: body),
          ],
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
            ? 'Sem resposta do servidor — verifique a conexão e toque em Receber de novo (não duplica a venda).'
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
