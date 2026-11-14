import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/session.dart';
import '../kit.dart';
import '../printing.dart';
import '../screens/receive_screen.dart';

const _statusLabels = {'open': 'Aberta', 'closing': 'Fechando', 'paid': 'Paga', 'canceled': 'Cancelada'};
const _tableStateLabels = {'free': 'Livre', 'open': 'Ocupada', 'closing': 'Fechando'};

enum _View { list, attach, rename, transfer, cancel, fee }

/// "Comandas da mesa": abrir, renomear, excluir, pedir conta, receber,
/// transferir, cancelar e retirar/reaplicar a taxa, por comanda. Espelha
/// `ComandasModal.vue`. Tudo online (conta ao vivo, sem fila). "Receber" abre
/// a tela de recebimento ([ReceiveScreen.comanda]).
///
/// Fecha com `'ended'` quando a mesa de origem foi encerrada (a última
/// comanda saiu dela).
class ComandasSheet extends StatefulWidget {
  const ComandasSheet({super.key});

  @override
  State<ComandasSheet> createState() => _ComandasSheetState();
}

class _ComandasSheetState extends State<ComandasSheet> {
  _View _view = _View.list;
  Comanda? _target;
  final _label = TextEditingController();
  final _reason = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _tableId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.session.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    app.session.removeListener(_changed);
    _label.dispose();
    _reason.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final error = await app.session.loadComandas();
    if (mounted && error != null) setState(() => _error = error);
  }

  void _go(_View view, [Comanda? comanda]) => setState(() {
    _view = view;
    _target = comanda;
    _error = null;
    _tableId = null;
    _label.text = view == _View.rename ? (comanda?.label ?? '') : '';
    _reason.clear();
    _email.clear();
    _password.clear();
  });

  /// Roda a ação; no sucesso volta para a lista.
  Future<void> _run(Future<String?> Function() action, {bool back = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (!mounted) return;
    _password.clear();
    setState(() {
      _busy = false;
      _error = error;
      if (error == null && back) {
        _view = _View.list;
        _target = null;
      }
    });
    if (error == null) app.tables.fetch();
  }

  ManagerOverride? _override(bool required) => required ? ManagerOverride(_email.text, _password.text) : null;
  bool _overrideReady(bool required) => !required || (_email.text.trim().isNotEmpty && _password.text.isNotEmpty);

  int _itemsOf(Comanda c) => c.itemsCount ?? (c.itemsSubtotal > 0.005 ? 1 : 0);

  Future<void> _pay(Comanda c) async {
    await Navigator.push<ReceiveResult>(
      context,
      MaterialPageRoute(builder: (_) => ReceiveScreen.comanda(comanda: c)),
    );
    if (!mounted) return;
    app.tables.fetch();
    await _load();
    if (!mounted) return;
    // Última comanda paga fecha a mesa no servidor.
    final status = app.session.session?.status;
    if (status == 'closed' || status == 'canceled') Navigator.pop(context, 'ended');
  }

  Future<void> _requestBill(Comanda c) async {
    await _run(() => app.session.requestComandaBill(c.id), back: false);
    if (!mounted || _error != null) return;
    if (app.settings.printBill && app.terminal.canPrint) {
      final fresh = app.session.comandas.where((x) => x.id == c.id).firstOrNull ?? c;
      await printComandaBill(context, fresh);
    }
  }

  Future<void> _transfer() async {
    final c = _target;
    final tableId = _tableId;
    if (c == null || tableId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await app.session.transferComanda(
      c.id,
      tableId,
      override: _override(app.session.transferRequiresPassword),
    );
    if (!mounted) return;
    _password.clear();
    if (r.error != null) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
      return;
    }
    app.tables.fetch();
    if (r.originEnded) {
      Navigator.pop(context, 'ended');
    } else {
      setState(() {
        _busy = false;
        _view = _View.list;
        _target = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => switch (_view) {
    _View.list => _list(),
    _View.attach => _attach(),
    _View.rename => _rename(),
    _View.transfer => _transferView(),
    _View.cancel => _cancelView(),
    _View.fee => _feeView(),
  };

  Widget _mini(String label, VoidCallback? onTap, {Color fg = C.zinc700, Color bg = C.white, Color? border = C.zinc200}) => Opacity(
    opacity: onTap == null ? 0.4 : 1,
    child: Tap(
      onTap: onTap,
      color: bg,
      radius: 8,
      border: border == null ? null : BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(label, style: T.xs(w: T.semibold, c: fg)),
    ),
  );

  Widget _list() {
    final store = app.session;
    final p = app.auth.permissions;
    final offline = !app.api.online.value;
    return SheetBody(
      title: 'Comandas da mesa',
      children: [
        if (offline) ...[
          const Note('Comandas e pagamentos exigem conexão.'),
          const SizedBox(height: 10),
        ],
        if (store.comandasLoading && store.comandas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Carregando...', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          )
        else if (store.comandas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Nenhuma comanda aberta nesta mesa.', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          ),
        for (final c in store.comandas)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.zinc200),
            ),
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
                          Text(c.label, style: T.base(w: T.bold)),
                          Text(_statusLabels[c.status] ?? c.status, style: T.xs(c: C.zinc500)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(brl(c.total), style: T.base(w: T.bold, c: C.primary700)),
                        if (c.remaining > 0.005 && c.status != 'paid')
                          Text('Falta ${brl(c.remaining)}', style: T.xs(c: C.amber600)),
                      ],
                    ),
                  ],
                ),
                if (c.serviceFee > 0.005) ...[
                  const SizedBox(height: 6),
                  KV('Itens', brl(c.itemsSubtotal)),
                  KV('Serviço (${percent(c.serviceFeePercentage)}%)', '+ ${brl(c.serviceFee)}'),
                ],
                if (c.couvert != null && c.couvert!.total > 0.005) KV('Couvert', '+ ${brl(c.couvert!.total)}'),
                if (c.isActive) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (p.manageComanda) _mini('Renomear', offline ? null : () => _go(_View.rename, c)),
                      if (p.manageComanda && _itemsOf(c) == 0 && !c.hasPayments)
                        _mini('Excluir', offline ? null : () => _run(() => app.session.removeComanda(c.id)), fg: C.red600),
                      if (p.transferTable) _mini('Transferir', offline ? null : () => _go(_View.transfer, c)),
                      if (p.cancelItem && _itemsOf(c) > 0 && !c.hasPayments)
                        _mini('Cancelar comanda', offline ? null : () => _go(_View.cancel, c), fg: C.red600),
                      if (p.serviceFeeRemove && c.serviceFee > 0.005 && !c.serviceFeeRemoved)
                        _mini('Retirar ${percent(c.serviceFeePercentage)}%', offline ? null : () => _go(_View.fee, c)),
                      if (p.serviceFeeRemove && c.serviceFeeRemoved)
                        _mini('Reaplicar taxa', offline || _busy ? null : () => _run(() => app.session.reapplyComandaFee(c.id))),
                      if (app.terminal.canPrint && _itemsOf(c) > 0)
                        _mini('Imprimir', () => printComandaBill(context, c)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (p.manageComanda && c.status == 'open')
                        Expanded(
                          child: Btn(
                            'Pedir conta',
                            kind: BtnKind.outline,
                            dense: true,
                            onTap: offline || _busy ? null : () => _requestBill(c),
                          ),
                        ),
                      if (p.reopenSession && c.status == 'closing')
                        Expanded(
                          child: Btn(
                            'Reabrir',
                            kind: BtnKind.outline,
                            dense: true,
                            onTap: offline || _busy ? null : () => _run(() => app.session.reopenComanda(c.id)),
                          ),
                        ),
                      if (p.processPayment) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Btn('Receber', dense: true, onTap: offline || c.remaining <= 0.005 ? null : () => _pay(c)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ErrText(_error, center: true),
        if (app.auth.permissions.manageComanda)
          Btn('+ Abrir comanda na mesa', kind: BtnKind.outline, onTap: offline ? null : () => _go(_View.attach)),
      ],
      footer: Btn('Fechar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
    );
  }

  Widget _attach() {
    final available = app.session.availableComandas;
    return SheetBody(
      title: 'Abrir comanda',
      children: [
        Text('Número ou nome da comanda:', style: T.xs(w: T.medium, c: C.zinc600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Field(
                controller: _label,
                hint: 'Ex.: 2 ou Maria',
                maxLength: 60,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _label.text.trim().isEmpty
                    ? null
                    : _run(() => app.session.attachComanda(label: _label.text.trim())),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: Btn(
                'Abrir',
                loading: _busy,
                onTap: _label.text.trim().isEmpty ? null : () => _run(() => app.session.attachComanda(label: _label.text.trim())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Ou selecione uma comanda cadastrada:', style: T.xs(w: T.medium, c: C.zinc600)),
        const SizedBox(height: 6),
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Nenhuma comanda disponível para abrir.', style: T.xs(c: C.zinc400)),
          )
        else
          ColGrid(
            cols: 3,
            children: [
              for (final a in available)
                Choice(a.label, selected: false, onTap: _busy ? null : () => _run(() => app.session.attachComanda(comandaTableId: a.id))),
            ],
          ),
        const SizedBox(height: 10),
        ErrText(_error, center: true),
      ],
      footer: Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => _go(_View.list)),
    );
  }

  Widget _rename() => SheetBody(
    title: 'Renomear ${_target?.label ?? ''}',
    children: [
      Field(
        controller: _label,
        hint: 'Número ou nome (ex.: 2 ou Maria)',
        maxLength: 60,
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      ErrText(_error, center: true),
    ],
    footer: BtnRow(
      Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => _go(_View.list)),
      Btn(
        _busy ? 'Salvando...' : 'Salvar',
        loading: _busy,
        onTap: _label.text.trim().isEmpty ? null : () => _run(() => app.session.renameComanda(_target!.id, _label.text.trim())),
      ),
    ),
  );

  Widget _transferView() {
    final tables = app.session.transferTables;
    final needs = app.session.transferRequiresPassword;
    return SheetBody(
      title: 'Transferir comanda ${_target?.label ?? ''}',
      subtitle: 'Mesa livre é aberta com a comanda; ocupada recebe a comanda.',
      children: [
        if (tables.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Nenhuma outra mesa disponível.', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          )
        else
          ColGrid(
            cols: 2,
            children: [
              for (final t in tables)
                Choice(
                  'Mesa ${t.number}\n${_tableStateLabels[t.state] ?? t.state}${t.areaName != null ? ' · ${t.areaName}' : ''}',
                  selected: _tableId == t.id,
                  onTap: () => setState(() => _tableId = t.id),
                ),
            ],
          ),
        const SizedBox(height: 10),
        if (needs) ...[
          OverrideFields(email: _email, password: _password, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
        ],
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => _go(_View.list)),
        Btn(
          _busy ? 'Transferindo...' : 'Transferir',
          loading: _busy,
          onTap: (_tableId != null && _overrideReady(needs)) ? _transfer : null,
        ),
      ),
    );
  }

  Widget _cancelView() {
    final needs = app.session.cancelRequiresPassword;
    return SheetBody(
      title: 'Cancelar comanda ${_target?.label ?? ''}',
      subtitle: 'Todos os itens da comanda serão cancelados. As outras comandas da mesa não mudam.',
      children: [
        Field(
          label: 'Motivo',
          controller: _reason,
          hint: 'Ex.: cliente foi embora',
          maxLength: 255,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (needs) ...[
          OverrideFields(email: _email, password: _password, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
        ],
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => _go(_View.list)),
        Btn(
          _busy ? 'Cancelando...' : 'Cancelar comanda',
          kind: BtnKind.danger,
          loading: _busy,
          onTap: (_reason.text.trim().isNotEmpty && _overrideReady(needs))
              ? () => _run(
                  () => app.session.cancelComandaItems(_target!.id, _reason.text.trim(), override: _override(needs)),
                )
              : null,
        ),
      ),
    );
  }

  Widget _feeView() {
    final c = _target!;
    final needs = app.session.session?.requireServiceFeeRemovalPassword ?? false;
    return SheetBody(
      title: 'Retirar ${percent(c.serviceFeePercentage)}% da comanda ${c.label}',
      subtitle: 'Taxa de serviço desta comanda: ${brl(c.serviceFee)}. As outras comandas da mesa não mudam.',
      children: [
        if (needs) ...[
          OverrideFields(email: _email, password: _password, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
        ],
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => _go(_View.list)),
        Btn(
          _busy ? 'Retirando...' : 'Retirar taxa',
          loading: _busy,
          onTap: _overrideReady(needs) ? () => _run(() => app.session.removeComandaFee(c.id, override: _override(needs))) : null,
        ),
      ),
    );
  }
}
