import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/order_draft.dart';
import '../kit.dart';
import '../order_widgets.dart';
import '../printing.dart';
import '../sheets/comandas_sheet.dart';
import '../sheets/items_sheet.dart';
import '../sheets/session_sheets.dart';
import '../sheets/tablet_code_sheet.dart';
import 'menu_screen.dart';
import 'receive_screen.dart';

/// Mesa aberta (seção 5.5 do layout novo): total, grade de opções, itens com
/// "Transferir" e "Cancelar" em cada linha, "Cancelar mesa" e a barra
/// "+ Itens · Pedir conta · Receber conta".
///
/// As 9 opções do antigo menu "Opções da mesa" estão todas aqui e nenhuma é
/// nova: seis na grade (QR do tablet, conta parcial, couvert, comandas,
/// transferir mesa, transferir item), duas na barra (pedir conta, receber
/// conta) e "Cancelar mesa" no fim da lista. Cada uma chama a rotina de
/// sempre. Opção sem permissão (ou que não cabe no estado da mesa) continua
/// no lugar, apagada, e explica o motivo ao toque.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId, this.title});
  final String sessionId;
  final String? title;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver, StoreRebuild {
  /// Pedido em montagem desta mesa: o Cardápio e a Revisão trabalham nele.
  /// Fica aqui para o carrinho sobreviver à ida e volta pelo botão "Conta".
  late final TableOrderDraft _draft = sessionDraft(sessionId: widget.sessionId, title: widget.title ?? 'Mesa');
  final _itemsKey = GlobalKey();
  String? _notice;
  bool _busy = false;

  /// Realce passageiro da lista de itens ("Transferir item" da grade).
  bool _highlightItems = false;
  Timer? _highlightTimer;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.session.addListener(rebuild);
    app.tables.addListener(rebuild);
    app.api.online.addListener(rebuild);
    _draft.addListener(rebuild);
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
    app.session.removeListener(rebuild);
    app.tables.removeListener(rebuild);
    app.api.online.removeListener(rebuild);
    _draft.removeListener(rebuild);
    _draft.dispose();
    _poll?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  SessionDetail? get _s => app.session.session?.id == widget.sessionId ? app.session.session : null;

  void _leave() => Navigator.pop(context);

  // ── Pedido ────────────────────────────────────────────────────────────────

  /// "+ Itens": Cardápio → Revisar pedido → enviar. O envio em si acontece na
  /// revisão (`TableOrderDraft.submit` → `SessionStore.sendCart`).
  Future<void> _addItems() async {
    final result = await openTableMenu(context, _draft);
    if (!mounted) return;
    if (result.exit == OrderFlowExit.tables) {
      _leave();
      return;
    }
    if (result.sent) setState(() => _notice = result.notice);
    app.session.fetch(widget.sessionId, silent: true);
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

  /// "Pedir conta": a mesma ação de sempre (a mesa vai para "fechando" e a
  /// conta é impressa, se a impressão estiver ligada). Depois volta ao mapa
  /// com o aviso.
  Future<void> _requestBill() async {
    final s = _s;
    if (s == null || _busy) return;
    if (s.activeItems.isEmpty) {
      toast(context, 'Adicione itens antes de pedir a conta.', error: true);
      return;
    }
    if (_draft.cart.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Há um pedido não enviado',
        message:
            'Os itens do carrinho (${_draft.cart.count}) ainda não foram lançados: não entram na conta e são '
            'descartados ao voltar para as mesas.',
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
    var printed = false;
    if (app.settings.printBill && app.terminal.canPrint) printed = await printSessionBill(context);
    if (!mounted) return;
    toast(context, billRequestedText(s.title, printed: printed));
    _leave();
  }

  /// "Receber conta": a tela de recebimento. Mesa com comandas recebe por
  /// comanda, então vai para "Comandas da mesa".
  Future<void> _receive() async {
    final s = _s;
    if (s == null) return;
    if (s.hasComandas) return _openComandas();
    final result = await Navigator.push<ReceiveResult>(
      context,
      MaterialPageRoute(builder: (_) => const ReceiveScreen.table()),
    );
    if (!mounted) return;
    app.tables.fetch();
    // "Voltar às mesas" na tela "Conta paga".
    if (result?.done == true) {
      _leave();
      return;
    }
    await app.session.fetch(widget.sessionId, silent: true);
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

  Future<void> _reopen() async {
    await _act(app.session.reopen, success: 'Mesa reaberta.');
    app.tables.fetch();
  }

  // ── Opções da grade ───────────────────────────────────────────────────────

  Future<void> _tabletCode() => showSheet<void>(context, (_) => const TabletCodeSheet());

  Future<void> _partialBill(SessionDetail s) async {
    final r = await showSheet<String>(context, (_) => PartialBillSheet(session: s));
    if (r == 'print' && mounted) await printSessionBill(context);
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

  Future<void> _transferTable() async {
    await app.tables.fetch();
    if (!mounted) return;
    final done = await showSheet<bool>(context, (_) => const TransferTableSheet());
    if (done == true && mounted) {
      app.tables.fetch();
      toast(context, 'Mesa transferida.');
      _leave();
    }
  }

  /// "Transferir item" da grade: com um item só, abre a janela de destino;
  /// com vários, mostra a lista e pede para escolher o item.
  void _transferItemOption(SessionDetail s) {
    final movable = s.activeItems.where((i) => i.canTransfer && hasTransferDestination(s, i)).toList();
    if (movable.isEmpty) {
      toast(context, 'Não há item que possa ser transferido agora.');
      return;
    }
    if (movable.length == 1 && s.activeItems.length == 1) {
      _transferItems([movable.first]);
      return;
    }
    final target = _itemsKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    _highlightTimer?.cancel();
    setState(() => _highlightItems = true);
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _highlightItems = false);
    });
    toast(context, 'Toque em "Transferir" no item que vai mudar de mesa.');
  }

  Future<void> _cancelSession(SessionDetail s) async {
    final done = await showSheet<bool>(context, (_) => CancelSessionSheet(session: s));
    if (done == true && mounted) {
      app.tables.fetch();
      toast(context, 'Mesa cancelada.');
      _leave();
    }
  }

  // ── Itens ─────────────────────────────────────────────────────────────────

  Future<void> _cancelItem(SessionItem item) async {
    final reason = await showSheet<String>(context, (_) => CancelItemSheet(item: item));
    if (reason == null || !mounted) return;
    final error = await app.session.cancelItem(item.id, reason);
    if (!mounted) return;
    if (error != null) {
      toast(context, error, error: true);
    } else {
      app.tables.fetch();
      toast(context, 'Item cancelado.');
    }
  }

  Future<void> _transferItems(List<SessionItem> items, {bool assignOnly = false}) async {
    final done = await showSheet<bool>(context, (_) => TransferItemSheet(items: items, assignOnly: assignOnly));
    if (done == true && mounted) {
      app.tables.fetch();
      toast(context, assignOnly ? 'Item atribuído.' : 'Item transferido.');
    }
  }

  // ── Cliente ───────────────────────────────────────────────────────────────

  Future<void> _editCustomer() async {
    final s = _s;
    if (s == null) return;
    final controller = TextEditingController(text: s.customerName ?? '');
    final name = await showSheet<String>(
      context,
      (ctx) => SheetBody(
        title: 'Nome do cliente',
        subtitle: 'Aparece na mesa e nas impressões.',
        children: [
          Field(
            controller: controller,
            hint: 'Ex.: João',
            maxLength: 120,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
        footer: BtnRow(
          Btn('Cancelar', kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx)),
          Btn('Salvar', kind: BtnKind.magenta, onTap: () => Navigator.pop(ctx, controller.text)),
        ),
      ),
    );
    if (name == null || !mounted) return;
    await _act(() => app.session.updateCustomer(name.trim().isEmpty ? null : name.trim()));
    app.tables.fetch();
  }

  Future<bool> _confirmLeave() async {
    if (_draft.cart.isEmpty) return true;
    return confirm(
      context,
      title: 'Descartar o pedido?',
      message: 'Os itens do carrinho (${_draft.cart.count}) ainda não foram enviados para a cozinha.',
      confirmLabel: 'Descartar',
      cancelLabel: 'Continuar',
      danger: true,
    );
  }

  /// Aviso de por que a opção está apagada.
  void _explain(String reason) => toast(context, reason);

  // ── Tela ──────────────────────────────────────────────────────────────────

  /// Quem abriu a mesa: o app só tem esse nome na lista do mapa.
  String? get _openedBy {
    for (final t in app.tables.tables) {
      if (t.session?.id == widget.sessionId) {
        final name = t.session?.openedByName?.trim();
        return (name == null || name.isEmpty) ? null : name;
      }
    }
    return null;
  }

  String _subtitle(SessionDetail s, {required bool canEdit}) {
    final customer = s.customerName?.trim() ?? '';
    final guests = s.guestCount;
    final openedBy = _openedBy;
    return [
      if (customer.isNotEmpty) customer else if (canEdit) '+ nome do cliente',
      ?openedBy,
      if (guests != null && guests > 0) guests == 1 ? '1 pessoa' : '$guests pessoas',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final store = app.session;
    final s = _s;
    final p = app.auth.permissions;
    final live = s != null && (s.isOpen || s.isClosing);

    Widget body;
    if (s == null && store.loading) {
      body = const StateView(text: 'Carregando a mesa...');
    } else if (s == null) {
      body = StateView(
        text: store.error ?? 'Não foi possível carregar a mesa.',
        error: true,
        onAction: () => store.fetch(widget.sessionId),
      );
    } else if (!live) {
      body = StateView(
        icon: Icons.check_circle_outline,
        text: s.status == 'closed' ? 'Mesa fechada.' : 'Mesa cancelada.',
        actionLabel: 'Voltar para as mesas',
        onAction: _leave,
      );
    } else {
      body = _content(s);
    }

    final title = s?.title ?? widget.title ?? 'Mesa';
    final subtitle = s == null ? '' : _subtitle(s, canEdit: p.openSession);

    return PopScope(
      canPop: _draft.cart.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          _draft.discard();
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(
          children: [
            AppHeader(
              title: title,
              onBack: () => Navigator.maybePop(context),
              // Título e subtítulo formam uma área de toque só (44 px): tocar
              // edita o nome do cliente, como antes.
              titleWidget: Semantics(
                button: s != null && p.openSession,
                label: s != null && p.openSession ? '$title, $subtitle, editar nome do cliente' : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: s != null && p.openSession ? _editCustomer : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.top),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.topSub),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!app.api.online.value) const Note('Sem conexão com o servidor.', radius: 0),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: live ? _bar(s) : null,
      ),
    );
  }

  /// A barra de 3 botões de largura igual. Botão que não cabe (permissão ou
  /// estado da mesa) fica apagado e explica o motivo ao toque.
  Widget _bar(SessionDetail s) {
    final p = app.auth.permissions;
    final hasItems = s.activeItems.isNotEmpty;
    final pendingCart = _draft.cart.count;

    final addBlocked = !p.createOrder
        ? 'Seu usuário não tem permissão para lançar pedidos.'
        : !s.isOpen
        ? 'A mesa está fechando: reabra a mesa para lançar itens.'
        : null;
    final billBlocked = !p.requestBill
        ? 'Seu usuário não tem permissão para pedir a conta.'
        : !s.isOpen
        ? 'A conta desta mesa já foi pedida.'
        : !hasItems
        ? 'Adicione itens antes de pedir a conta.'
        : null;
    final receiveBlocked = s.hasComandas
        ? (!p.manageComanda ? 'Seu usuário não tem permissão para gerenciar comandas.' : null)
        : !p.processPayment
        ? 'Seu usuário não tem permissão para receber pagamentos.'
        : !hasItems
        ? 'A mesa ainda não tem itens.'
        : s.bill.settled
        ? 'A conta desta mesa já está quitada.'
        : null;

    Widget button(String label, BtnKind kind, VoidCallback onTap, String? blocked, {bool loading = false}) =>
        blocked == null
        ? Btn(label, kind: kind, loading: loading, onTap: onTap)
        : Opacity(
            opacity: 0.4,
            child: Btn(label, kind: kind, onTap: () => _explain(blocked)),
          );

    return BottomBar.trio(
      button(pendingCart == 0 ? '+ Itens' : '+ Itens ($pendingCart)', BtnKind.green, _addItems, addBlocked),
      button('Pedir conta', BtnKind.navy, _requestBill, billBlocked, loading: _busy && billBlocked == null),
      button('Receber conta', BtnKind.magenta, _receive, receiveBlocked),
    );
  }

  Widget _content(SessionDetail s) {
    final p = app.auth.permissions;
    final active = s.activeItems;
    final hasItems = active.isNotEmpty;
    final settled = s.bill.settled && s.bill.paid > 0.005;
    final pendingCart = _draft.cart.count;
    final units = active.fold<int>(0, (a, i) {
      final q = i.quantity;
      return a + (q == q.roundToDouble() ? q.toInt() : 1);
    });
    final comandaLabels = {for (final c in s.comandas) c.id: c.label};

    String permission(String what) => 'Seu usuário não tem permissão para $what.';
    final options = <_Option>[
      _Option(
        Icons.qr_code_2,
        'Gerar QR do tablet na mesa',
        _tabletCode,
        blocked: !p.openSession
            ? permission('gerar o QR do tablet')
            : !s.isOpen
            ? 'A mesa está fechando: reabra a mesa para gerar o QR do tablet.'
            : null,
      ),
      _Option(Icons.format_list_bulleted, 'Ver conta parcial', () => _partialBill(s)),
      _Option(
        Icons.music_note_outlined,
        'Lançar couvert',
        _openCouvert,
        blocked: !p.couvertAdd
            ? permission('lançar couvert')
            : !s.isOpen
            ? 'A mesa está fechando: reabra a mesa para lançar couvert.'
            : null,
      ),
      _Option(
        Icons.credit_card_outlined,
        'Comandas da mesa',
        _openComandas,
        blocked: !p.manageComanda
            ? permission('gerenciar comandas')
            : !(s.enableComandas || s.hasComandas)
            ? 'Esta loja não usa comandas dentro da mesa.'
            : null,
      ),
      _Option(
        Icons.swap_horiz,
        'Transferir mesa',
        _transferTable,
        blocked: !p.transferTable ? permission('transferir mesa') : null,
      ),
      _Option(
        Icons.swap_horiz,
        'Transferir item',
        () => _transferItemOption(s),
        blocked: !p.transferItem
            ? permission('transferir itens')
            : !hasItems
            ? 'A mesa ainda não tem itens para transferir.'
            : null,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (settled) ...[_settledBanner(s), const SizedBox(height: 12)] else if (s.isClosing) ...[
          _closingBanner(s),
          const SizedBox(height: 12),
        ],
        if (pendingCart > 0) ...[
          Note(
            pendingCart == 1
                ? 'Há 1 item no carrinho ainda não enviado para a cozinha. Toque para continuar o pedido.'
                : 'Há $pendingCart itens no carrinho ainda não enviados para a cozinha. Toque para continuar o pedido.',
            radius: 12,
            center: false,
            onTap: s.isOpen && p.createOrder ? _addItems : null,
          ),
          const SizedBox(height: 12),
        ],
        if (_notice != null) ...[
          Note(_notice!, radius: 12, center: false, onTap: () => setState(() => _notice = null)),
          const SizedBox(height: 12),
        ],
        if (s.pendingTabletOrders.isNotEmpty) ...[_tabletOrders(s), const SizedBox(height: 12)],
        _total(s),
        const SizedBox(height: 12),
        ColGrid(
          cols: 3,
          children: [
            for (final o in options) _OptionTile(option: o, onBlocked: _explain),
          ],
        ),
        const SizedBox(height: 12),
        if (s.hasComandas) _unassigned(s, active),
        SectionLabel(
          'Itens da mesa',
          key: _itemsKey,
          trailing: Text(units == 1 ? '1 ITEM' : '$units ITENS', style: T.section),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _highlightItems ? C.magenta : C.white, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12.5, vertical: 2.5),
          child: active.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    p.createOrder && s.isOpen
                        ? 'Nenhum item na mesa. Toque em "+ Itens" para lançar.'
                        : 'Nenhum item na mesa.',
                    style: T.body(c: C.sub),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, item) in active.indexed)
                      _ItemRow(
                        key: ValueKey(item.id),
                        item: item,
                        comanda: item.comandaId == null ? null : comandaLabels[item.comandaId],
                        last: i == active.length - 1,
                        canTransfer: p.transferItem && item.canTransfer,
                        hasDestination: hasTransferDestination(s, item),
                        canCancel: p.cancelItem && item.canCancel,
                        onTransfer: () => _transferItems([item]),
                        onCancel: () => _cancelItem(item),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        // "Cancelar mesa": separado das outras ações, só texto vermelho.
        Opacity(
          opacity: p.cancelSession ? 1 : 0.4,
          child: Tap(
            onTap: p.cancelSession ? () => _cancelSession(s) : () => _explain(permission('cancelar a mesa')),
            color: C.white,
            radius: 14,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text('Cancelar mesa', style: T.s(13, w: T.bold, c: C.cancel, h: 1.3)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Cartão navy "Total da mesa": o total e as parcelas que o servidor
  /// devolve em `bill`. Nada é calculado aqui.
  Widget _total(SessionDetail s) {
    final b = s.bill;
    final parts = [
      'Itens ${brl(b.itemsSubtotal)}',
      if (b.couvertAmount > 0.005) 'Couvert ${brl(b.couvertAmount)}',
      if (b.discount > 0.005) 'Desconto - ${brl(b.discount)}',
      if (b.serviceFee > 0.005) 'Taxa de serviço ${percent(b.serviceFeePercentage)}% ${brl(b.serviceFee)}',
      if (b.paid > 0.005) 'Pago ${brl(b.paid)}',
      if (b.paid > 0.005) 'Restante ${brl(b.remaining)}',
    ];
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Total da mesa', style: T.s(12, c: C.navySub, h: 1.3)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(brl(b.total), maxLines: 1, style: T.num(28, c: C.white, h: 1.2)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 14,
              runSpacing: 3,
              children: [
                for (final t in parts) Text(t, style: T.num(11.5, w: T.medium, c: C.navySub, h: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textAction(String label, VoidCallback? onTap, {Color color = C.navy}) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(label, style: T.s(13, w: T.bold, c: color, h: 1.3)),
          ),
        ),
      ),
    ),
  );

  /// Mesa "fechando": a conta foi pedida e falta receber.
  Widget _closingBanner(SessionDetail s) {
    final p = app.auth.permissions;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(color: const Color(0xFFFFEEDF), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20, color: C.orangeText),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Conta solicitada. Aguardando pagamento.',
                style: T.s(13, w: T.semibold, c: C.orangeText, h: 1.35),
              ),
            ),
          ),
          if (p.reopenSession) _textAction('Reabrir mesa', _busy ? null : _reopen),
        ],
      ),
    );
  }

  /// Conta quitada e mesa ainda não fechada no servidor.
  Widget _settledBanner(SessionDetail s) {
    final p = app.auth.permissions;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 20, color: C.greenText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conta quitada. Aguardando fechamento da mesa.',
                  style: T.s(13, w: T.semibold, c: C.greenText, h: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (p.closeSession)
            Btn('Fechar mesa', kind: BtnKind.navy, loading: _busy, onTap: _closeSession)
          else
            Text(
              'Seu usuário não tem permissão para fechar a mesa. Chame quem pode concluir.',
              style: T.s(12, c: C.greenText, h: 1.35),
            ),
          if (s.isClosing && p.reopenSession)
            Align(alignment: Alignment.centerRight, child: _textAction('Reabrir mesa', _busy ? null : _reopen)),
        ],
      ),
    );
  }

  /// Itens sem comanda (mesa com comandas): a mesa só fecha depois que forem
  /// atribuídos. O mesmo bloco da antiga tela "Itens da comanda".
  Widget _unassigned(SessionDetail s, List<SessionItem> active) {
    final p = app.auth.permissions;
    final unassigned = active.where((i) => i.comandaId == null).toList();
    if (unassigned.isEmpty) return const SizedBox.shrink();
    final assignable = unassigned.where((i) => i.canTransfer).toList();
    final canAssign = p.createOrder && s.openComandas.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: C.red50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.red200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  unassigned.length == 1 ? '1 item sem comanda' : '${unassigned.length} itens sem comanda',
                  style: T.s(13.5, w: T.bold, c: C.red800, h: 1.3),
                ),
              ),
              if (canAssign && assignable.length > 1)
                _textAction(
                  'Atribuir todos (${assignable.length})',
                  () => _transferItems(assignable, assignOnly: true),
                  color: C.red700,
                ),
            ],
          ),
          Text(
            'A mesa só fecha depois que estes itens forem atribuídos a uma comanda.',
            style: T.s(12, c: C.red800, h: 1.35),
          ),
          for (final i in unassigned)
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${qty(i.quantity)}x ${i.productName}', style: T.body(c: C.ink)),
                  ),
                ),
                if (canAssign && i.canTransfer)
                  _textAction('Atribuir', () => _transferItems([i], assignOnly: true), color: C.red700),
              ],
            ),
          if (!canAssign && s.openComandas.isEmpty)
            Text('Abra uma comanda em "Comandas da mesa".', style: T.s(12, w: T.semibold, c: C.red700, h: 1.35)),
        ],
      ),
    );
  }

  /// Pedidos feitos no TABLET da mesa: só entram na conta e vão para a
  /// cozinha depois que o garçom libera.
  Widget _tabletOrders(SessionDetail s) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.amber50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.amber200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PEDIDO DO TABLET AGUARDANDO LIBERAÇÃO', style: T.section.copyWith(color: C.amber800)),
        for (final o in s.pendingTabletOrders)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final i in o.items)
                  Text(
                    '${qty(i.quantity)}x ${i.productName}${i.notes != null ? ' (${i.notes})' : ''}',
                    style: T.body(),
                  ),
                if (app.auth.permissions.sendOrder) ...[
                  const SizedBox(height: 8),
                  Btn(
                    'Liberar para a cozinha',
                    kind: BtnKind.green,
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

/// Uma opção da grade da mesa.
class _Option {
  const _Option(this.icon, this.label, this.onTap, {this.blocked});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Por que não pode agora (`null` = pode). A opção continua na grade,
  /// apagada, e o toque mostra este texto.
  final String? blocked;
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.onBlocked});
  final _Option option;
  final ValueChanged<String> onBlocked;

  @override
  Widget build(BuildContext context) {
    final blocked = option.blocked;
    return Semantics(
      button: true,
      enabled: blocked == null,
      child: Opacity(
        opacity: blocked == null ? 1 : 0.4,
        child: Tap(
          onTap: blocked == null ? option.onTap : () => onBlocked(blocked),
          color: C.white,
          radius: 14,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(option.icon, size: 22, color: C.navy),
                  const SizedBox(height: 6),
                  Text(
                    option.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(11.5, w: T.semibold, c: C.ink, h: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Um item da mesa: quantidade e nome, o que foi escolhido, os links
/// "Transferir" e "Cancelar", o status atual e o valor.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.last,
    required this.canTransfer,
    required this.hasDestination,
    required this.canCancel,
    required this.onTransfer,
    required this.onCancel,
    this.comanda,
  });
  final SessionItem item;
  final String? comanda;
  final bool last;
  final bool canTransfer;
  final bool hasDestination;
  final bool canCancel;
  final VoidCallback onTransfer;
  final VoidCallback onCancel;

  Widget _link(String label, Color color, VoidCallback? onTap) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '$label ${item.productName}',
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: T.s(12, w: T.bold, c: color, h: 1.2),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.flavorsLabel.isNotEmpty) item.flavorsLabel,
      if (item.addonsLabel.isNotEmpty) '+ ${item.addonsLabel}',
      if (item.notes != null && item.notes!.isNotEmpty) item.notes!,
    ].join(' · ');
    final links = canTransfer || canCancel;
    return Container(
      padding: EdgeInsets.only(top: 11, bottom: links ? 0 : 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${qty(item.quantity)}x ${item.productName}', style: T.body(w: T.semibold)),
                if (details.isNotEmpty)
                  Text(
                    details,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(12, c: C.sub, h: 1.35),
                  ),
                if (comanda != null) Text('Comanda $comanda', style: T.s(12, w: T.semibold, c: C.navy, h: 1.35)),
                if (links)
                  // `Wrap`: em tela estreita ou letra grande os links descem
                  // de linha em vez de estourar a largura.
                  Wrap(
                    children: [
                      if (canTransfer) _link('Transferir', const Color(0xFF2F3BD6), hasDestination ? onTransfer : null),
                      if (canCancel) _link('Cancelar', C.cancel, onCancel),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ItemStatusTag(item.status),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 62),
            child: Text(brl(item.total), textAlign: TextAlign.right, maxLines: 1, style: T.num(13.5)),
          ),
        ],
      ),
    );
  }
}
