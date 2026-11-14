import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/session.dart';
import '../kit.dart';

/// Há para onde transferir este item? (outra mesa aberta, uma mesa livre ou
/// outra comanda desta mesa). Sem destino, o link "Transferir" fica apagado.
bool hasTransferDestination(SessionDetail s, SessionItem item) {
  if (s.freeTables.isNotEmpty) return true;
  for (final t in s.transferTargets) {
    if (!t.isCurrent) return true;
    if (t.comandas.any((c) => c.id != item.comandaId)) return true;
  }
  return false;
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
              '${widget.assignOnly ? ' Abra uma nova comanda em "Comandas da mesa".' : ''}',
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
