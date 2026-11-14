import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/order_draft.dart';
import '../kit.dart';
import '../order_widgets.dart';
import '../printing.dart';
import 'menu_screen.dart';

/// Aviso de pedido gravado que não chegou na produção (`kitchen_sent == false`).
const kitchenNotSentNotice = 'Pedido gravado, mas NÃO saiu na produção. Avise a cozinha. Não lance de novo.';

/// Revisar pedido (5.4 do plano): os dados da mesa, os itens novos (ainda
/// não enviados) e os já lançados, com "+ Itens" e "Enviar para cozinha".
///
/// Mesa livre: é aqui que ficam os campos do antigo formulário "Abrir mesa"
/// (pessoas, cliente e comandas). A mesa só é aberta no servidor ao enviar.
///
/// Fecha com `null` ("+ Itens" ou voltar: continua no cardápio) ou com um
/// [OrderFlowResult] depois do envio ("Voltar às mesas" / "Ficar na mesa").
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.draft});
  final TableOrderDraft draft;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> with StoreRebuild {
  final _customer = TextEditingController();
  final _customerFocus = FocusNode();
  final _comanda = TextEditingController();

  /// O nome do cliente da mesa aberta já foi copiado para o campo?
  bool _customerSynced = false;
  String? _error;

  TableOrderDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    draft.addListener(rebuild);
    app.session.addListener(rebuild);
    app.menu.addListener(rebuild);
    app.api.online.addListener(rebuild);
    _customerFocus.addListener(_onCustomerFocus);
    if (draft.isNewTable) {
      _customer.text = draft.customerName;
      _customerSynced = true;
    } else {
      _ensureSession();
      _syncCustomer();
    }
  }

  @override
  void dispose() {
    draft.removeListener(rebuild);
    app.session.removeListener(rebuild);
    app.menu.removeListener(rebuild);
    app.api.online.removeListener(rebuild);
    _customer.dispose();
    _customerFocus.dispose();
    _comanda.dispose();
    super.dispose();
  }

  @override
  void onStoreChanged() => _syncCustomer();

  /// A sessão desta mesa, se for a carregada no store.
  SessionDetail? get _s => app.session.session?.id == draft.sessionId ? app.session.session : null;

  void _ensureSession() {
    final id = draft.sessionId;
    if (id != null && _s == null && !app.session.loading) app.session.fetch(id, silent: true);
  }

  /// Mesa já aberta: o campo "Cliente" nasce com o nome atual.
  void _syncCustomer() {
    if (_customerSynced) return;
    final s = _s;
    if (s == null) return;
    _customer.text = s.customerName ?? '';
    _customerSynced = true;
  }

  // ── Cliente da mesa aberta ────────────────────────────────────────────────

  void _onCustomerFocus() {
    if (!_customerFocus.hasFocus) _saveCustomer();
  }

  /// Gravação do nome em andamento (para o envio esperar por ela).
  Future<String?>? _customerSaving;

  /// Mesa já aberta: grava o nome pela rotina de sempre (`updateCustomer`).
  /// Devolve a mensagem de erro ou `null`.
  Future<String?> _saveCustomer() => _customerSaving ??= _doSaveCustomer().whenComplete(() => _customerSaving = null);

  Future<String?> _doSaveCustomer() async {
    final s = _s;
    if (draft.isNewTable || s == null || !app.auth.permissions.openSession) return null;
    final name = _customer.text.trim();
    if (name == (s.customerName ?? '').trim()) return null;
    final error = await app.session.updateCustomer(name.isEmpty ? null : name);
    if (!mounted) return error;
    if (error != null) {
      toast(context, error, error: true);
    } else {
      app.tables.fetch();
    }
    return error;
  }

  // ── Comandas da mesa nova ─────────────────────────────────────────────────

  void _addComanda() {
    draft.addComandaLabel(_comanda.text);
    _comanda.clear();
    setState(() => _error = null);
  }

  // ── Enviar ────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    if (draft.busy || draft.cart.isEmpty) return;
    setState(() => _error = null);
    if (draft.isNewTable) {
      // Como o botão "Abrir mesa" fazia: o que está digitado também vale.
      if (draft.withComandas && _comanda.text.trim().isNotEmpty) _addComanda();
      draft.customerName = _customer.text;
    } else {
      // O nome alterado é gravado antes do pedido (sai na via impressa).
      await _saveCustomer();
      if (!mounted) return;
    }
    FocusScope.of(context).unfocus();

    final result = await draft.submit();
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _error = result.error);
      // A mesa pode ter sido aberta agora: a tela passa a tratá-la como aberta.
      _ensureSession();
      return;
    }

    // Via do pedido, se ligada em Configurações. Não espera: a janela abre já
    // e mostra o erro da impressora se ele vier. Se o garçom fechar a janela
    // antes, o erro aparece como aviso na tela seguinte.
    final printing = app.settings.printOrders && app.terminal.canPrint
        ? printOrderTicket(
            tableLabel: draft.title,
            comandaLabel: result.comandaLabel,
            customerName: result.customerName,
            items: result.items,
          )
        : null;
    var sheetOpen = true;
    final root = Navigator.of(context, rootNavigator: true).context;
    printing?.then((error) {
      if (error != null && !sheetOpen && root.mounted) toast(root, 'Impressão: $error', error: true);
    });
    final exit = await showSheet<OrderFlowExit>(
      context,
      (_) =>
          _SentSheet(count: result.count, tableTitle: draft.title, kitchenSent: result.kitchenSent, printing: printing),
      dismissible: false,
    );
    sheetOpen = false;
    if (!mounted) return;
    Navigator.pop(
      context,
      OrderFlowResult(
        exit ?? OrderFlowExit.tables,
        sessionId: result.sessionId,
        notice: result.kitchenSent ? null : kitchenNotSentNotice,
      ),
    );
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cart = draft.cart;
    final s = _s;
    final busy = draft.busy;
    final waiter = app.auth.user?.name.trim() ?? '';
    final unavailable = cart.items.any((i) => app.menu.isUnavailable(i.product.id));
    final sent = s?.activeItems ?? const <SessionItem>[];

    return PopScope(
      // Enquanto envia, o "voltar" do aparelho não sai da tela.
      canPop: !busy,
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(
          children: [
            AppHeader(
              title: 'Revisar pedido',
              subtitle: [draft.title, if (waiter.isNotEmpty) waiter].join(' · '),
              onBack: busy ? null : () => Navigator.pop(context),
            ),
            if (!app.api.online.value) const Note('Sem conexão com o servidor.', radius: 0),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _tableCard(s),
                  const SizedBox(height: 12),
                  if (unavailable) ...[
                    const Note('O cardápio mudou: há item indisponível no pedido. Remova antes de enviar.'),
                    const SizedBox(height: 12),
                  ],
                  SectionLabel('Novos · ainda não enviados', trailing: Tag(itemsCountLabel(cart.count))),
                  CardBox(
                    padding: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: cart.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('Nenhum item novo.', style: T.body(c: C.sub)),
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
                                    enabled: !busy,
                                  ),
                              ],
                            ),
                    ),
                  ),
                  if (sent.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SectionLabel('Já lançados nesta mesa'),
                    CardBox(
                      padding: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, item) in sent.indexed) _SentLine(item: item, last: i == sent.length - 1),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) Note(_error!, kind: NoteKind.error, radius: 0),
          ],
        ),
        bottomNavigationBar: BottomBar.duo(
          Btn('+ Itens', kind: BtnKind.green, onTap: busy ? null : () => Navigator.pop(context)),
          CountBtn(
            icon: Icons.send_outlined,
            label: 'Enviar para cozinha',
            total: cart.total,
            loading: busy,
            onTap: cart.isEmpty ? null : _send,
          ),
        ),
      ),
    );
  }

  /// Uma linha do cartão da mesa: nome à esquerda, controle à direita.
  Widget _row(String label, Widget control, {bool first = false}) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    decoration: BoxDecoration(
      border: first ? null : const Border(top: BorderSide(color: C.line)),
    ),
    child: Row(
      children: [
        Text(label, style: T.body(w: T.bold)),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: control),
        ),
      ],
    ),
  );

  /// Pessoas, cliente e comandas (os campos do antigo "Abrir mesa").
  Widget _tableCard(SessionDetail? s) {
    final isNew = draft.isNewTable;
    final busy = draft.busy;
    final canEditCustomer = isNew || (s != null && app.auth.permissions.openSession);
    final guests = isNew ? draft.guestCount : (s?.guestCount ?? draft.guestCount);

    final Widget people = isNew
        ? QtyStepper(
            // Zero = não informado, como o campo vazio do formulário antigo.
            value: '${guests ?? 0}',
            onMinus: !busy && guests != null ? () => draft.setGuestCount(guests - 1) : null,
            onPlus: !busy && (guests ?? 0) < 100 ? () => draft.setGuestCount((guests ?? 0) + 1) : null,
          )
        : Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              guests != null && guests > 0 ? '$guests' : 'Não informado',
              style: guests != null && guests > 0 ? T.num(14) : T.body(c: C.sub),
            ),
          );

    return CardBox(
      padding: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Pessoas na mesa', people, first: true),
            _row(
              'Cliente',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: TextField(
                  controller: _customer,
                  focusNode: _customerFocus,
                  enabled: canEditCustomer && !busy,
                  inputFormatters: [LengthLimitingTextInputFormatter(120)],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  onChanged: isNew ? (v) => draft.customerName = v : null,
                  onSubmitted: (_) => _saveCustomer(),
                  style: T.body(w: T.medium),
                  decoration: fieldDecoration(
                    hint: 'Nome (opcional)',
                    focus: C.magenta,
                  ).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                ),
              ),
            ),
            if (isNew && draft.allowComandas) ...[
              _row(
                'Comandas',
                _Segmented(
                  left: 'Somente mesa',
                  right: 'Com comandas',
                  rightSelected: draft.withComandas,
                  onChanged: busy ? null : draft.setWithComandas,
                ),
              ),
              if (draft.withComandas) _newComandas(),
            ],
            if (!isNew && s != null && s.hasComandas) _openComandas(s),
          ],
        ),
      ),
    );
  }

  /// Mesa nova "com comandas": os rótulos a criar e, havendo mais de um, em
  /// qual lançar este pedido.
  Widget _newComandas() {
    final labels = draft.comandaLabels;
    final typed = _comanda.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Field(
                  controller: _comanda,
                  hint: 'Nº ou nome (ex.: 2 ou Maria)',
                  maxLength: 60,
                  focus: C.magenta,
                  enabled: !draft.busy,
                  onSubmitted: (_) => _addComanda(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Adicionar comanda',
                child: Opacity(
                  opacity: typed ? 1 : 0.4,
                  child: Tap(
                    onTap: typed && !draft.busy ? _addComanda : null,
                    color: C.white,
                    radius: 12,
                    border: const BorderSide(color: C.line, width: 1.5),
                    child: const SizedBox(width: 44, height: 44, child: Icon(Icons.add, size: 20, color: C.ink)),
                  ),
                ),
              ),
            ],
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(labels.length > 1 ? 'LANÇAR ESTE PEDIDO NA COMANDA' : 'COMANDA DESTE PEDIDO', style: T.section),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              children: [
                for (final label in labels)
                  _ComandaChip(
                    label: label,
                    selected: labels.length == 1 || draft.comandaLabel == label,
                    onTap: draft.busy
                        ? null
                        : () {
                            draft.chooseComandaLabel(label);
                            setState(() => _error = null);
                          },
                    onRemove: draft.busy ? null : () => draft.removeComandaLabel(label),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text('Você também pode abrir mais comandas depois, na tela da mesa.', style: T.s(11.5, c: C.sub, h: 1.35)),
        ],
      ),
    );
  }

  /// Mesa já aberta com comandas: a comanda que recebe o pedido (obrigatória).
  Widget _openComandas(SessionDetail s) {
    final open = s.openComandas;
    final target = draft.targetComandaId;
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('LANÇAR NA COMANDA', style: T.section),
          const SizedBox(height: 2),
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'Nenhuma comanda aberta. Abra uma na tela da mesa.',
                style: T.s(12.5, w: T.medium, c: C.orangeText, h: 1.35),
              ),
            )
          else
            Wrap(
              spacing: 6,
              children: [
                for (final c in open)
                  _ComandaChip(
                    label: c.label,
                    selected: target == c.id,
                    onTap: draft.busy
                        ? null
                        : () {
                            draft.chooseComanda(c.id);
                            setState(() => _error = null);
                          },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Item já lançado na mesa, com o status que o app mostra.
class _SentLine extends StatelessWidget {
  const _SentLine({required this.item, required this.last});
  final SessionItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.flavorsLabel.isNotEmpty) item.flavorsLabel,
      if (item.addonsLabel.isNotEmpty) '+ ${item.addonsLabel}',
      if (item.notes != null && item.notes!.isNotEmpty) item.notes!,
    ].join(' · ');
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(12, c: C.sub, h: 1.35),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ItemStatusTag(item.status),
        ],
      ),
    );
  }
}

/// "Somente mesa | Com comandas".
class _Segmented extends StatelessWidget {
  const _Segmented({required this.left, required this.right, required this.rightSelected, this.onChanged});
  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool>? onChanged;

  Widget _option(String label, bool value) {
    final active = rightSelected == value;
    return Flexible(
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? C.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: T.s(12.5, w: T.bold, c: active ? C.white : C.sub, h: 1.2),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [_option(left, false), const SizedBox(width: 4), _option(right, true)],
    ),
  );
}

/// Comanda selecionável (e removível, na mesa nova).
class _ComandaChip extends StatelessWidget {
  const _ComandaChip({required this.label, required this.selected, this.onTap, this.onRemove});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // 44 px de toque em volta de um chip de 32.
    constraints: const BoxConstraints(minHeight: 44),
    child: Center(
      widthFactor: 1,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: selected ? C.magentaSoft : C.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? C.magenta : C.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              selected: selected,
              label: 'Comanda $label',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, onRemove == null ? 12 : 6, 0),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: T.s(12.5, w: T.bold, c: selected ? C.magentaText : C.ink, h: 1.2),
                    ),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              Semantics(
                button: true,
                label: 'Remover comanda $label',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                    child: Icon(Icons.close, size: 15, color: selected ? C.magentaText : C.sub),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Janela "Pedido na cozinha!": confirma o envio e pergunta para onde ir.
/// Mostra também o aviso de produção (`kitchen_sent == false`) e o erro da
/// impressora, quando houver.
class _SentSheet extends StatefulWidget {
  const _SentSheet({required this.count, required this.tableTitle, required this.kitchenSent, this.printing});
  final int count;
  final String tableTitle;
  final bool kitchenSent;

  /// Impressão da via em andamento; completa com a mensagem de erro ou `null`.
  final Future<String?>? printing;

  @override
  State<_SentSheet> createState() => _SentSheetState();
}

class _SentSheetState extends State<_SentSheet> {
  String? _printError;

  @override
  void initState() {
    super.initState();
    widget.printing?.then((error) {
      if (mounted && error != null) setState(() => _printError = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.kitchenSent;
    return SheetBody(
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: ok ? C.greenSoft : C.amber100, shape: BoxShape.circle),
            child: Icon(
              ok ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 34,
              color: ok ? C.green : C.orangeText,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          ok ? 'Pedido na cozinha!' : 'Pedido gravado',
          textAlign: TextAlign.center,
          style: T.s(21, w: T.bold, c: C.ink, h: 1.25),
        ),
        const SizedBox(height: 4),
        Text(
          sentItemsText(widget.count, widget.tableTitle),
          textAlign: TextAlign.center,
          style: T.body(c: C.sub),
        ),
        if (!ok) ...[const SizedBox(height: 12), const Note(kitchenNotSentNotice)],
        if (_printError != null) ...[const SizedBox(height: 12), Note('Impressão: $_printError', kind: NoteKind.error)],
        const SizedBox(height: 4),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Btn('Voltar às mesas', kind: BtnKind.navy, onTap: () => Navigator.pop(context, OrderFlowExit.tables)),
          const SizedBox(height: 8),
          Btn(
            stayOnTableText(widget.tableTitle),
            kind: BtnKind.secondary,
            onTap: () => Navigator.pop(context, OrderFlowExit.stay),
          ),
        ],
      ),
    );
  }
}
