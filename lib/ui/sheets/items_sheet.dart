import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/session.dart';
import '../kit.dart';
import 'session_sheets.dart';

const _statusLabel = {
  'pending': 'Aguardando',
  'preparing': 'Preparando',
  'ready': 'Pronto',
  'delivered': 'Entregue',
  'canceled': 'Cancelado',
};

const _statusColors = <String, (Color, Color)>{
  'pending': (C.amber100, C.amber700),
  'preparing': (C.sky100, C.sky700),
  'ready': (C.green100, C.green700),
  'delivered': (C.zinc100, C.zinc500),
  'canceled': (C.red100, C.red500),
};

/// "Itens da comanda": tudo que foi lançado na mesa, com cancelar/transferir
/// por item, os itens sem comanda e o resumo da conta. Espelha
/// `SessionItemsModal.vue`. Fecha com `'request-bill'` quando o operador pede
/// a conta daqui.
class SessionItemsScreen extends StatefulWidget {
  const SessionItemsScreen({super.key});

  @override
  State<SessionItemsScreen> createState() => _SessionItemsScreenState();
}

class _SessionItemsScreenState extends State<SessionItemsScreen> {
  @override
  void initState() {
    super.initState();
    app.session.addListener(_changed);
  }

  @override
  void dispose() {
    app.session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _hasDestination(SessionDetail s, SessionItem item) {
    if (s.freeTables.isNotEmpty) return true;
    for (final t in s.transferTargets) {
      if (!t.isCurrent) return true;
      if (t.comandas.any((c) => c.id != item.comandaId)) return true;
    }
    return false;
  }

  Future<void> _cancel(SessionItem item) async {
    final reason = await showSheet<String>(context, (_) => CancelItemSheet(item: item));
    if (reason == null || !mounted) return;
    final error = await app.session.cancelItem(item.id, reason);
    if (!mounted) return;
    if (error != null) {
      toast(context, error, error: true);
    } else {
      app.tables.fetch();
    }
  }

  Future<void> _transfer(List<SessionItem> items, {bool assignOnly = false}) async {
    final done = await showSheet<bool>(context, (_) => TransferItemSheet(items: items, assignOnly: assignOnly));
    if (done == true && mounted) {
      app.tables.fetch();
      toast(context, assignOnly ? 'Item atribuído.' : 'Item transferido.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = app.session.session;
    if (s == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(title: 'Itens da comanda', onBack: () => Navigator.pop(context)),
            const Expanded(child: StateView(text: 'Mesa não carregada.')),
          ],
        ),
      );
    }
    final p = app.auth.permissions;
    final items = s.activeItems;
    final unassigned = s.hasComandas ? items.where((i) => i.comandaId == null).toList() : const <SessionItem>[];
    final assignable = unassigned.where((i) => i.canTransfer).toList();
    final canAssign = p.createOrder && s.openComandas.isNotEmpty;
    final comandaLabels = {for (final c in s.comandas) c.id: c.label};

    return Scaffold(
      backgroundColor: C.white,
      body: Column(
        children: [
          AppHeader(title: 'Itens da comanda', subtitle: s.title, onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                if (unassigned.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.red50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.red200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Itens sem comanda (${unassigned.length})', style: T.sm(w: T.bold, c: C.red800)),
                            ),
                            if (canAssign && assignable.length > 1)
                              Tap(
                                onTap: () => _transfer(assignable, assignOnly: true),
                                color: C.white,
                                radius: 8,
                                border: const BorderSide(color: C.red300),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: Text('Atribuir todos (${assignable.length})', style: T.xs(w: T.semibold, c: C.red700)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('A mesa só fecha depois que estes itens forem atribuídos a uma comanda.', style: T.xs(c: C.red800)),
                        const SizedBox(height: 6),
                        for (final i in unassigned)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text('${qty(i.quantity)}× ${i.productName}', style: T.sm(c: C.zinc800))),
                                if (canAssign && i.canTransfer)
                                  Tap(
                                    onTap: () => _transfer([i], assignOnly: true),
                                    color: C.white,
                                    radius: 8,
                                    border: const BorderSide(color: C.red300),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    child: Text('Atribuir a comanda', style: T.xs(w: T.semibold, c: C.red700)),
                                  ),
                              ],
                            ),
                          ),
                        if (!canAssign && s.openComandas.isEmpty)
                          Text('Abra uma comanda em "Opções da mesa" › Comandas.', style: T.xs(c: C.red700)),
                      ],
                    ),
                  ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text('Nenhum item na comanda.', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
                  ),
                for (final item in items) _itemTile(s, item, comandaLabels),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: C.white, border: Border(top: BorderSide(color: C.zinc200))),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BillSummary(bill: s.bill, totalLabel: 'Total da comanda'),
                if (s.isOpen && p.requestBill) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Btn('Pedir conta', onTap: items.isEmpty ? null : () => Navigator.pop(context, 'request-bill')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(SessionDetail s, SessionItem item, Map<String, String> comandaLabels) {
    final p = app.auth.permissions;
    final (bg, fg) = _statusColors[item.status] ?? (C.zinc100, C.zinc500);
    final canTransfer = p.transferItem && item.canTransfer;
    final canCancel = p.cancelItem && item.canCancel;
    final comanda = item.comandaId == null ? null : comandaLabels[item.comandaId];
    final time = hhmm(item.createdAt);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.zinc100))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${qty(item.quantity)}× ${item.productName}', style: T.sm(w: T.semibold)),
                    if (item.flavorsLabel.isNotEmpty) Text(item.flavorsLabel, style: T.xs(c: C.zinc500)),
                    if (item.addonsLabel.isNotEmpty) Text('+ ${item.addonsLabel}', style: T.xs(c: C.zinc500)),
                    if (item.notes != null) Text(item.notes!, style: T.xs(c: C.zinc400)),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: brl(item.total),
                        style: T.xs(w: T.medium, c: C.zinc700),
                        children: [
                          if (time.isNotEmpty) TextSpan(text: ' · $time', style: T.xs(c: C.zinc400)),
                          if (comanda != null) TextSpan(text: ' · Comanda $comanda', style: T.xs(c: C.primary500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(_statusLabel[item.status] ?? item.status, bg: bg, fg: fg, size: 11, bold: false),
            ],
          ),
          if (canTransfer || canCancel)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canTransfer)
                    Opacity(
                      opacity: _hasDestination(s, item) ? 1 : 0.4,
                      child: Tap(
                        onTap: _hasDestination(s, item) ? () => _transfer([item]) : null,
                        color: C.white,
                        radius: 8,
                        border: const BorderSide(color: C.zinc200),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text('Transferir', style: T.xs(w: T.semibold, c: C.zinc700)),
                      ),
                    ),
                  if (canCancel) ...[
                    const SizedBox(width: 8),
                    Tap(
                      onTap: () => _cancel(item),
                      color: C.red50,
                      radius: 8,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text('Cancelar', style: T.xs(w: T.semibold, c: C.red600)),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Destino da transferência de item(ns): outra mesa aberta, mesa livre (abre
/// e transfere) ou uma comanda. `assignOnly` = atribuir item sem comanda a
/// uma comanda DESTA mesa.
class TransferItemSheet extends StatefulWidget {
  const TransferItemSheet({super.key, required this.items, this.assignOnly = false});
  final List<SessionItem> items;
  final bool assignOnly;

  @override
  State<TransferItemSheet> createState() => _TransferItemSheetState();
}

class _TransferItemSheetState extends State<TransferItemSheet> {
  final _search = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _quantity = TextEditingController(text: '$_maxQuantity');
  String? _sessionId;
  String? _freeTableId;
  String? _comandaId;
  bool _busy = false;
  String? _error;

  SessionDetail get _s => app.session.session!;
  bool get _single => widget.items.length == 1;

  /// Quantidade inteira > 1 pode ser transferida em parte.
  int get _maxQuantity {
    final q = widget.items.first.quantity;
    return (_single && q == q.roundToDouble()) ? q.toInt() : 1;
  }

  @override
  void initState() {
    super.initState();
    if (widget.assignOnly) {
      _sessionId = _s.transferTargets.where((t) => t.isCurrent).firstOrNull?.id ?? _s.id;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _email.dispose();
    _password.dispose();
    _quantity.dispose();
    super.dispose();
  }

  TransferTarget? get _target => _s.transferTargets.where((t) => t.id == _sessionId).firstOrNull;

  bool get _isCurrent => _target?.isCurrent ?? (widget.assignOnly && _sessionId == _s.id);

  /// Comandas que podem receber: as `open` do destino, menos a de origem.
  List<({String id, String label})> get _comandaOptions {
    final origin = widget.items.map((i) => i.comandaId).toSet();
    final list = _target?.comandas ?? (widget.assignOnly ? [for (final c in _s.openComandas) (id: c.id, label: c.label)] : const []);
    return list.where((c) => !(_isCurrent && origin.length == 1 && origin.contains(c.id))).toList();
  }

  bool get _needsComanda => _sessionId != null && (_isCurrent || (_target?.hasActiveComandas ?? false));

  bool get _needsAuthorizer {
    if (!_s.requireTransferItemPassword) return false;
    final fromComanda = widget.items.any((i) => i.comandaId != null);
    final assignToOwn = _isCurrent && !fromComanda;
    return (_comandaId != null || _isCurrent || fromComanda) && !assignToOwn;
  }

  bool get _ready {
    if (_busy) return false;
    if (_sessionId == null && _freeTableId == null) return false;
    if (_needsComanda && _comandaId == null) return false;
    if (_needsAuthorizer && (_email.text.trim().isEmpty || _password.text.isEmpty)) return false;
    if (_single && _maxQuantity > 1) {
      final q = int.tryParse(_quantity.text.trim()) ?? 0;
      if (q < 1 || q > _maxQuantity) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_ready) return;
    if (_freeTableId != null) {
      final ok = await confirm(
        context,
        title: 'Abrir a mesa e transferir?',
        message: 'A mesa de destino está livre: ela será aberta para receber o(s) item(ns).',
        confirmLabel: 'Abrir e transferir',
        cancelLabel: 'Não',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final q = int.tryParse(_quantity.text.trim()) ?? _maxQuantity;
    final error = await app.session.transferItems(
      [for (final i in widget.items) i.id],
      targetSessionId: _sessionId,
      targetTableId: _freeTableId,
      targetComandaId: _comandaId,
      quantity: (_single && q < _maxQuantity) ? q : null,
      override: _needsAuthorizer ? ManagerOverride(_email.text, _password.text) : null,
    );
    if (!mounted) return;
    _password.clear();
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = fold(_search.text.trim());
    bool match(String label) => q.isEmpty || fold(label).contains(q);
    final targets = _s.transferTargets.where((t) => match(t.label)).toList();
    final free = app.auth.permissions.openSession ? _s.freeTables.where((t) => match(t.label)).toList() : <FreeTable>[];
    final options = _comandaOptions;

    return SheetBody(
      title: widget.assignOnly ? 'Atribuir a comanda' : (_single ? 'Transferir item' : 'Transferir itens'),
      subtitle: _single ? widget.items.first.productName : '${widget.items.length} itens',
      children: [
        if (_single && _maxQuantity > 1) ...[
          Field(
            label: 'Quantidade (de $_maxQuantity)',
            controller: _quantity,
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
        if (!widget.assignOnly) ...[
          Text('MESA DE DESTINO', style: T.label),
          const SizedBox(height: 6),
          if (_s.transferTargets.length + _s.freeTables.length > 8) ...[
            Field(controller: _search, hint: 'Buscar mesa por número/área...', onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
          ],
          if (targets.isEmpty && free.isEmpty)
            Text('Sem mesa ou comanda para receber.', style: T.xs(c: C.amber600)),
          if (targets.isNotEmpty) ...[
            Text('Mesas abertas', style: T.xs(c: C.zinc400)),
            const SizedBox(height: 4),
            ColGrid(
              cols: 2,
              children: [
                for (final t in targets)
                  Choice(t.label, selected: _sessionId == t.id, onTap: () => setState(() {
                    _sessionId = t.id;
                    _freeTableId = null;
                    _comandaId = null;
                    _error = null;
                  })),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (free.isNotEmpty) ...[
            Text('Mesas livres', style: T.xs(c: C.zinc400)),
            const SizedBox(height: 4),
            ColGrid(
              cols: 2,
              children: [
                for (final t in free)
                  Choice(t.label, selected: _freeTableId == t.id, onTap: () => setState(() {
                    _freeTableId = t.id;
                    _sessionId = null;
                    _comandaId = null;
                    _error = null;
                  })),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (_needsComanda) ...[
          Text('COMANDA DE DESTINO', style: T.label),
          const SizedBox(height: 6),
          if (options.isEmpty)
            Text(
              'Esta mesa não tem comanda aberta para receber o item.'
              '${widget.assignOnly ? ' Abra uma nova comanda em "Opções da mesa" › Comandas.' : ''}',
              style: T.xs(c: C.amber600),
            )
          else
            ColGrid(
              cols: 3,
              children: [
                for (final c in options)
                  Choice('Comanda ${c.label}', selected: _comandaId == c.id, onTap: () => setState(() {
                    _comandaId = c.id;
                    _error = null;
                  })),
              ],
            ),
          const SizedBox(height: 10),
        ],
        if (_needsAuthorizer) ...[
          OverrideFields(email: _email, password: _password, title: 'Autorização do gerente', onChanged: () => setState(() {})),
          const SizedBox(height: 10),
        ],
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Cancelar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(
          _busy ? (widget.assignOnly ? 'Atribuindo…' : 'Transferindo…') : (widget.assignOnly ? 'Atribuir' : 'Transferir'),
          loading: _busy,
          onTap: _ready ? _submit : null,
        ),
      ),
    );
  }
}
