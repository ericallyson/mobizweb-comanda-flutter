import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/uuid.dart';
import '../../models/models.dart';
import '../../print/receipt.dart';
import '../catalog.dart';
import '../kit.dart';
import '../printing.dart';
import '../sheets/comandas_sheet.dart';
import '../sheets/items_sheet.dart';
import '../sheets/receive_sheet.dart';
import '../sheets/session_sheets.dart';
import 'product_screen.dart';

/// A mesa aberta: cardápio para lançar, carrinho, itens, conta e recebimento.
/// Espelha `TableSessionView.vue` do PWA.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId, this.title});
  final String sessionId;
  final String? title;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  final _cart = <CartItem>[];

  /// Chave de idempotência ESTÁVEL do carrinho atual: reenviar depois de um
  /// timeout não duplica o pedido. Troca quando o envio é confirmado.
  String _cartKey = uuidV7();
  String? _lastComandaId;
  String? _notice;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.session.addListener(_changed);
    app.session.fetch(widget.sessionId);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ModalRoute.of(context)?.isCurrent ?? false) app.session.fetch(widget.sessionId, silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.ledger.reconcileOrphan().then((_) => app.session.fetch(widget.sessionId, silent: true));
      app.menu.revalidate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.session.removeListener(_changed);
    _poll?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  SessionDetail? get _s => app.session.session?.id == widget.sessionId ? app.session.session : null;

  double get _cartTotal => _cart.fold(0, (a, i) => a + i.total);
  int get _cartCount => _cart.fold(0, (a, i) => a + (i.product.allowFractionalQty ? 1 : i.quantity.round()));

  void _leave() => Navigator.pop(context);

  // ── Pedido ────────────────────────────────────────────────────────────────

  Future<void> _selectProduct(MenuProduct product) async {
    FocusScope.of(context).unfocus();
    final item = await Navigator.push<CartItem>(
      context,
      MaterialPageRoute(builder: (_) => ProductScreen(product: product), fullscreenDialog: true),
    );
    if (item != null && mounted) setState(() => _cart.add(item));
  }

  Future<void> _openCart() async {
    final s = _s;
    if (s == null) return;
    await showSheet<bool>(
      context,
      (_) => CartSheet(
        title: 'Pedido atual (não enviado)',
        cart: _cart,
        onChanged: _changed,
        comandas: s.openComandas,
        requireComanda: s.hasComandas,
        initialComandaId: _lastComandaId,
        actionLabel: (total) => 'Enviar para a cozinha (${brl(total)})',
        onAction: _send,
      ),
    );
    _changed();
  }

  /// Envia o carrinho. Devolve a mensagem de erro ou `null`.
  Future<String?> _send(String? comandaId) async {
    final s = _s;
    if (s == null) return 'Mesa não carregada.';
    if (_cart.any((i) => app.menu.isUnavailable(i.product.id))) {
      return 'Há item indisponível no pedido. Remova antes de enviar.';
    }
    final sent = List<CartItem>.of(_cart);
    final result = await app.session.sendCart(widget.sessionId, sent, comandaId: comandaId, idempotencyKey: _cartKey);
    if (!result.ok) return result.error;

    _lastComandaId = comandaId;
    _cart.clear();
    _cartKey = uuidV7();
    _notice = result.kitchenSent
        ? null
        : 'Pedido gravado, mas NÃO saiu na produção. Avise a cozinha — não lance de novo.';
    app.tables.fetch();
    if (mounted) {
      toast(context, 'Pedido enviado.');
      if (app.settings.printOrders && app.terminal.canPrint) {
        final comandaLabel = comandaId == null ? null : s.comandas.where((c) => c.id == comandaId).firstOrNull?.label;
        // Sem `await`: a folha do carrinho fecha enquanto a via imprime.
        unawaited(
          printOrderTicket(
            context,
            tableLabel: s.title,
            comandaLabel: comandaLabel,
            customerName: s.customerName,
            items: sent,
          ),
        );
      }
    }
    return null;
  }

  // ── Conta ─────────────────────────────────────────────────────────────────

  Future<void> _act(Future<String?> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      toast(context, error, error: true);
    } else if (success != null) {
      toast(context, success);
    }
  }

  Future<void> _requestBill() async {
    final s = _s;
    if (s == null || _busy) return;
    if (s.activeItems.isEmpty) {
      toast(context, 'Adicione itens antes de pedir a conta.', error: true);
      return;
    }
    if (_cart.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Há um pedido não enviado',
        message: 'Os ${_cart.length} item(ns) do carrinho ainda não foram lançados e não entram na conta.',
        confirmLabel: 'Pedir conta assim mesmo',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final error = await app.session.requestBill();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      toast(context, 'Não foi possível solicitar a conta. $error', error: true);
      return;
    }
    app.tables.fetch();
    if (app.settings.printBill && app.terminal.canPrint) await printSessionBill(context);
  }

  Future<void> _receive() async {
    final s = _s;
    if (s == null) return;
    final paid = await showSheet<bool>(
      context,
      (_) => ReceiveSheet(kind: 'session', targetId: s.id, label: s.title, remaining: s.bill.remaining),
    );
    if (paid != true || !mounted) return;
    await app.session.fetch(widget.sessionId, silent: true);
    app.tables.fetch();
    if (!mounted) return;
    await _afterPayment();
  }

  /// Depois de um recebimento: mesa quitada fecha sozinha no servidor (se o
  /// operador pode fechar); aqui só oferece o comprovante e volta ao mapa.
  Future<void> _afterPayment() async {
    final s = app.session.session;
    if (s == null) return;
    final closed = s.status == 'closed';
    if (!closed && !s.bill.settled) {
      toast(context, 'Pagamento registrado. Falta ${brl(s.bill.remaining)}.');
      return;
    }
    if (app.terminal.canPrint && app.settings.printBill) {
      final print = await confirm(
        context,
        title: closed ? 'Mesa fechada' : 'Conta quitada',
        message: 'Imprimir o comprovante da conta?',
        confirmLabel: 'Imprimir',
        cancelLabel: 'Não',
      );
      if (print && mounted) await _printReceipt('COMPROVANTE');
    } else if (mounted) {
      toast(context, closed ? 'Mesa fechada.' : 'Conta quitada.');
    }
    if (closed && mounted) _leave();
  }

  Future<void> _printReceipt(String title) async {
    try {
      final receipt = await app.session.fetchReceipt();
      final error = await app.terminal.printLines(billReceipt(receipt, guestCount: _s?.guestCount, title: title));
      if (error != null && mounted) toast(context, 'Impressão: $error', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, 'Não foi possível montar o comprovante: ${e.message}', error: true);
    }
  }

  Future<void> _closeSession() async {
    await _act(app.session.closeSession);
    if (!mounted) return;
    app.tables.fetch();
    if (app.session.session?.status == 'closed') {
      toast(context, 'Mesa fechada.');
      _leave();
    }
  }

  // ── Opções ────────────────────────────────────────────────────────────────

  Future<void> _openItems() async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SessionItemsScreen(), fullscreenDialog: true),
    );
    if (action == 'request-bill' && mounted) await _requestBill();
  }

  Future<void> _openOptions() async {
    final s = _s;
    if (s == null) return;
    final action = await showSheet<String>(context, (_) => TableOptionsSheet(session: s));
    if (action == null || !mounted) return;
    switch (action) {
      case 'request-bill':
        await _requestBill();
      case 'partial-bill':
        final r = await showSheet<String>(context, (_) => PartialBillSheet(session: s));
        if (r == 'print' && mounted) await printSessionBill(context);
      case 'print-bill':
        await printSessionBill(context);
      case 'couvert':
        await _openCouvert();
      case 'receive':
        await _receive();
      case 'comandas':
        await _openComandas();
      case 'transfer-table':
        await app.tables.fetch();
        if (!mounted) return;
        final done = await showSheet<bool>(context, (_) => const TransferTableSheet());
        if (done == true && mounted) {
          app.tables.fetch();
          toast(context, 'Mesa transferida.');
          _leave();
        }
      case 'transfer-item':
        await _openItems();
      case 'reopen':
        await _act(app.session.reopen, success: 'Mesa reaberta.');
        app.tables.fetch();
      case 'cancel-session':
        final done = await showSheet<bool>(context, (_) => CancelSessionSheet(session: s));
        if (done == true && mounted) {
          app.tables.fetch();
          toast(context, 'Mesa cancelada.');
          _leave();
        }
    }
  }

  Future<void> _openComandas() async {
    final r = await showSheet<String>(context, (_) => const ComandasSheet());
    if (!mounted) return;
    app.tables.fetch();
    if (r == 'ended') {
      _leave();
    } else {
      await app.session.fetch(widget.sessionId, silent: true);
    }
  }

  Future<void> _openCouvert() async {
    final s = _s;
    if (s == null) return;
    List<Comanda>? comandas;
    if (s.hasActiveComandas) {
      final error = await app.session.loadComandas();
      if (!mounted) return;
      if (error != null) {
        toast(context, error, error: true);
        return;
      }
      comandas = app.session.comandas.where((c) => c.status == 'open').toList();
    }
    final done = await showSheet<bool>(context, (_) => CouvertSheet(session: s, comandas: comandas));
    if (done == true && mounted) app.tables.fetch();
  }

  Future<void> _editCustomer() async {
    final s = _s;
    if (s == null) return;
    final controller = TextEditingController(text: s.customerName ?? '');
    final name = await showSheet<String>(
      context,
      (ctx) => SheetBody(
        padding: 24,
        children: [
          Text('Nome do cliente', style: T.lg(w: T.bold, c: C.primary700)),
          const SizedBox(height: 14),
          Field(
            controller: controller,
            hint: 'Ex: João — aparece na mesa e nas impressões',
            maxLength: 120,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
        footer: BtnRow(
          Btn('Cancelar', kind: BtnKind.outline, onTap: () => Navigator.pop(ctx)),
          Btn('Salvar', kind: BtnKind.accent, onTap: () => Navigator.pop(ctx, controller.text)),
        ),
      ),
    );
    if (name == null || !mounted) return;
    await _act(() => app.session.updateCustomer(name.trim().isEmpty ? null : name.trim()));
    app.tables.fetch();
  }

  Future<bool> _confirmLeave() async {
    if (_cart.isEmpty) return true;
    return confirm(
      context,
      title: 'Descartar o pedido?',
      message: 'Os ${_cart.length} item(ns) do carrinho ainda não foram enviados para a cozinha.',
      confirmLabel: 'Descartar',
      cancelLabel: 'Continuar',
      danger: true,
    );
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = app.session;
    final s = _s;
    final p = app.auth.permissions;

    Widget body;
    if (s == null && store.loading) {
      body = const StateView(text: 'Carregando comanda...');
    } else if (s == null) {
      body = StateView(
        text: store.error ?? 'Não foi possível carregar a comanda.',
        error: true,
        onAction: () => store.fetch(widget.sessionId),
      );
    } else if (s.status == 'closed' || s.status == 'canceled') {
      body = StateView(
        icon: Icons.check_circle_outline,
        text: s.status == 'closed' ? 'Mesa fechada.' : 'Mesa cancelada.',
        actionLabel: 'Voltar para as mesas',
        onAction: _leave,
      );
    } else {
      body = _content(s);
    }

    return PopScope(
      canPop: _cart.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          _cart.clear();
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: C.zinc50,
        body: Column(
          children: [
            AppHeader(
              title: s?.title ?? widget.title ?? 'Mesa',
              onBack: () => Navigator.maybePop(context),
              subtitleWidget: s == null
                  ? null
                  : GestureDetector(
                      onTap: p.openSession ? _editCustomer : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '${s.customerName ?? '+ nome do cliente'}'
                              '${s.guestCount != null && s.guestCount! > 0 ? ' · ${s.guestCount} pessoa(s)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.xs(c: C.primary200),
                            ),
                          ),
                          if (p.openSession) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_outlined, size: 12, color: C.primary200),
                          ],
                        ],
                      ),
                    ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _content(SessionDetail s) {
    final p = app.auth.permissions;
    final active = s.activeItems;
    final unassigned = s.hasComandas
        ? (s.unassignedItemsCount ?? active.where((i) => i.comandaId == null).length)
        : 0;
    final offline = !app.api.online.value;

    return Column(
      children: [
        // Ações rápidas (grid de 3).
        Container(
          decoration: const BoxDecoration(color: C.white, border: Border(bottom: BorderSide(color: C.zinc200))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Tap(
                  onTap: _openItems,
                  color: C.white,
                  border: const BorderSide(color: C.zinc200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Ver itens', style: T.xs(w: T.semibold, c: C.zinc700)),
                      if (active.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: C.primary600, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            '${active.length}',
                            textAlign: TextAlign.center,
                            style: T.s(11, w: T.bold, c: C.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (p.requestBill) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Btn(
                    'Pedir conta',
                    dense: true,
                    loading: _busy,
                    onTap: (!s.isOpen || active.isEmpty) ? null : _requestBill,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(child: Btn('Opções da mesa', kind: BtnKind.outline, dense: true, onTap: _openOptions)),
            ],
          ),
        ),
        if (offline) const Note('Sem conexão com o servidor.', radius: 0),
        if (s.pendingTabletOrders.isNotEmpty) _tabletOrders(s),
        if (unassigned > 0)
          Container(
            color: C.red50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: unassigned == 1 ? '1 item sem comanda' : '$unassigned itens sem comanda',
                      style: T.xs(w: T.bold, c: C.red800),
                      children: [
                        TextSpan(text: ' — atribua a uma comanda antes de fechar a mesa.', style: T.xs(c: C.red800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tap(
                  onTap: _openItems,
                  color: C.white,
                  radius: 8,
                  border: const BorderSide(color: C.red300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Ver itens', style: T.xs(w: T.semibold, c: C.red700)),
                ),
              ],
            ),
          ),
        if (_notice != null) Note(_notice!, radius: 0, onTap: () => setState(() => _notice = null)),
        Expanded(
          child: s.isOpen
              ? (p.createOrder
                    ? CatalogBrowser(onSelect: _selectProduct)
                    : const StateView(text: 'Seu usuário não tem permissão para lançar pedidos.'))
              : _closingView(s),
        ),
        if (s.isOpen && _cart.isNotEmpty)
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
                  child: Text('$_cartCount', style: T.sm(w: T.bold, c: C.white)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Ver pedido (${brl(_cartTotal)})', style: T.sm(w: T.semibold, c: C.white))),
                const Icon(Icons.chevron_right, color: C.white),
              ],
            ),
          ),
      ],
    );
  }

  Widget _closingView(SessionDetail s) {
    final p = app.auth.permissions;
    final settled = s.bill.settled;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                settled ? Icons.check_circle_outline : Icons.receipt_long_outlined,
                size: 40,
                color: settled ? C.emerald600 : C.orange600,
              ),
              const SizedBox(height: 10),
              Text(
                settled ? 'Conta quitada — aguardando fechamento da mesa.' : 'Conta solicitada — aguardando pagamento.',
                textAlign: TextAlign.center,
                style: T.sm(w: T.medium, c: C.zinc600),
              ),
              const SizedBox(height: 6),
              bigMoney(settled ? s.bill.total : s.bill.remaining, size: 22),
              if (!settled && s.bill.paid > 0.005)
                Text(
                  'Total ${brl(s.bill.total)} · pago ${brl(s.bill.paid)}',
                  textAlign: TextAlign.center,
                  style: T.xs(c: C.zinc500),
                ),
              const SizedBox(height: 16),
              if (!settled && !s.hasComandas && p.processPayment) ...[
                Btn('Receber pagamento', icon: Icons.credit_card, onTap: _receive),
                const SizedBox(height: 10),
              ],
              if (!settled && s.hasComandas && p.manageComanda) ...[
                Btn('Comandas da mesa', icon: Icons.list_alt_outlined, onTap: _openComandas),
                const SizedBox(height: 10),
              ],
              if (settled && p.closeSession) ...[
                Btn('Fechar mesa', loading: _busy, onTap: _closeSession),
                const SizedBox(height: 10),
              ],
              if (settled && !p.closeSession)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Seu usuário não tem permissão para fechar a mesa. Chame quem pode concluir.',
                    textAlign: TextAlign.center,
                    style: T.xs(c: C.zinc500),
                  ),
                ),
              if (app.terminal.canPrint) ...[
                Btn('Imprimir conta', kind: BtnKind.outline, icon: Icons.print_outlined, onTap: () => printSessionBill(context)),
                const SizedBox(height: 10),
              ],
              Btn('Ver itens', kind: BtnKind.outline, onTap: _openItems),
              if (p.reopenSession) ...[
                const SizedBox(height: 10),
                Tap(
                  onTap: _busy
                      ? null
                      : () async {
                          await _act(app.session.reopen, success: 'Mesa reaberta.');
                          app.tables.fetch();
                        },
                  color: C.white,
                  border: const BorderSide(color: C.primary600),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Reabrir mesa', textAlign: TextAlign.center, style: T.sm(w: T.semibold, c: C.primary600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Pedidos feitos no TABLET da mesa: só entram na conta e vão para a
  /// cozinha depois que o garçom libera.
  Widget _tabletOrders(SessionDetail s) => Container(
    width: double.infinity,
    color: C.amber50,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PEDIDO DO TABLET AGUARDANDO LIBERAÇÃO', style: T.xs(w: T.bold, c: C.amber800)),
        for (final o in s.pendingTabletOrders)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.amber200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final i in o.items)
                  Text(
                    '${qty(i.quantity)}× ${i.productName}${i.notes != null ? ' (${i.notes})' : ''}',
                    style: T.sm(c: C.zinc700),
                  ),
                if (app.auth.permissions.sendOrder) ...[
                  const SizedBox(height: 8),
                  Btn(
                    'Liberar para a cozinha',
                    kind: BtnKind.success,
                    dense: true,
                    loading: _busy,
                    onTap: () => _act(() => app.session.approveTabletOrder(o.id), success: 'Pedido liberado.'),
                  ),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}
