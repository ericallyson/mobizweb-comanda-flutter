import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/counter.dart';
import '../../stores/order_draft.dart';
import '../kit.dart';
import '../order_widgets.dart';
import '../printing.dart';
import 'menu_screen.dart';
import 'receive_screen.dart';

/// Venda de balcão (5.7 do plano): o mesmo Cardápio da mesa, a tela "Venda de
/// balcão" para conferir os itens e o recebimento numa tacada só. 100%
/// online; a chave de idempotência por carrinho impede venda duplicada quando
/// a resposta se perde.
///
/// É a tela que a aba "Balcão" abre. "Receber" leva à tela "Receber venda"
/// ([ReceiveScreen.counter]), que termina em "Venda recebida".
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

  /// Abre "Receber venda". Devolve `true` quando a venda foi registrada (o
  /// operador já viu "Venda recebida" e pediu uma nova venda).
  Future<bool> _checkout() async {
    if (_cart.isEmpty) return false;
    if (_cart.items.any((i) => app.menu.isUnavailable(i.product.id))) {
      toast(context, 'Há item indisponível na venda. Remova antes de receber.', error: true);
      return false;
    }
    final items = _cart.items;
    final result = await Navigator.push<ReceiveResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiveScreen.counter(
          counter: CounterSaleRequest(
            total: _total,
            methods: app.counter.context?.methods ?? const [],
            parts: _parts,
            items: items,
            cartKey: _cart.key,
            onSold: (sale, payments, customerName) => _sold(sale, payments, customerName, items),
          ),
        ),
      ),
    );
    if (!mounted) return false;
    _syncLock();
    setState(() {});
    return result?.done == true;
  }

  /// Venda gravada: as transações da maquininha deixam de estar pendentes, o
  /// carrinho é zerado e saem o comprovante e as fichas (o que estiver ligado).
  Future<void> _sold(
    CounterSaleResult sale,
    List<CounterPayment> payments,
    String? customerName,
    List<CartItem> items,
  ) async {
    await app.ledger.settle(payments.map((p) => p.atk).whereType<String>());
    _parts.clear();
    _cart.commit();
    _syncLock();
    if (!mounted) return;
    // Sem `await`: a tela "Venda recebida" aparece enquanto o comprovante e as
    // fichas imprimem.
    unawaited(
      printAfterCounterSale(
        context,
        sale: sale,
        items: items,
        payments: [for (final p in payments) (label: p.label, amount: p.amount)],
        customerName: customerName,
      ),
    );
  }

  Future<void> _back() async {
    if (_cart.isEmpty) {
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
      canPop: _cart.isEmpty,
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
}

/// "Venda de balcão": a lista dos itens com −/+ e o total, "+ Itens" (volta
/// ao cardápio) e "Receber".
class CounterSaleScreen extends StatefulWidget {
  const CounterSaleScreen({super.key, required this.cart, required this.onReceive});
  final OrderCart cart;

  /// Abre "Receber venda". Devolve `true` quando a venda foi registrada: esta
  /// tela fecha e o balcão volta ao cardápio, pronto para a próxima venda.
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
