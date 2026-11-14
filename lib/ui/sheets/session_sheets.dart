import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../stores/session.dart';
import '../kit.dart';

// ── Opções da mesa ───────────────────────────────────────────────────────────

/// Menu "Opções da mesa". Fecha devolvendo a ação escolhida.
class TableOptionsSheet extends StatelessWidget {
  const TableOptionsSheet({super.key, required this.session});
  final SessionDetail session;

  @override
  Widget build(BuildContext context) {
    final p = app.auth.permissions;
    final isOpen = session.isOpen;
    final isClosing = session.isClosing;
    final hasItems = session.activeItems.isNotEmpty;
    final hasComandas = session.hasComandas;

    Widget opt(String action, IconData icon, String label, {bool enabled = true, bool danger = false}) => Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Tap(
        onTap: enabled ? () => Navigator.pop(context, action) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? C.red500 : C.zinc600),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: T.sm(w: T.medium, c: danger ? C.red500 : C.zinc800))),
          ],
        ),
      ),
    );

    return SheetBody(
      children: [
        Text('OPÇÕES DA MESA', style: T.sm(w: T.bold, c: C.zinc400)),
        const SizedBox(height: 8),
        if (isOpen && p.requestBill) opt('request-bill', Icons.receipt_long_outlined, 'Pedir conta', enabled: hasItems),
        opt('partial-bill', Icons.visibility_outlined, 'Ver conta parcial'),
        if (app.terminal.canPrint && hasItems) opt('print-bill', Icons.print_outlined, 'Imprimir conta'),
        if (p.couvertAdd && isOpen)
          opt('couvert', Icons.theater_comedy_outlined, session.couvert != null ? 'Couvert (alterar pessoas)' : 'Lançar couvert'),
        if (p.processPayment && !hasComandas && (isOpen || isClosing) && hasItems)
          opt('receive', Icons.credit_card, 'Receber conta'),
        if (p.manageComanda && (isOpen || isClosing) && (session.enableComandas || hasComandas))
          opt('comandas', Icons.list_alt_outlined, 'Comandas da mesa'),
        if (p.transferTable && (isOpen || isClosing)) opt('transfer-table', Icons.shuffle, 'Transferir mesa'),
        if (p.transferItem && hasItems) opt('transfer-item', Icons.swap_horiz, 'Transferir item'),
        if (p.reopenSession && isClosing) opt('reopen', Icons.lock_open_outlined, 'Reabrir mesa'),
        if (p.cancelSession) opt('cancel-session', Icons.delete_outline, 'Cancelar mesa', danger: true),
      ],
      footer: Btn('Fechar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
    );
  }
}

// ── Conta parcial ────────────────────────────────────────────────────────────

class PartialBillSheet extends StatelessWidget {
  const PartialBillSheet({super.key, required this.session});
  final SessionDetail session;

  @override
  Widget build(BuildContext context) {
    final items = session.activeItems;
    final bill = session.bill;
    final guests = session.guestCount;
    return SheetBody(
      title: 'Conta parcial — ${session.title}',
      subtitle: (guests != null && guests > 0) ? '$guests pessoa(s)' : null,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('Nenhum item consumido ainda.', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          ),
        for (final i in items)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.zinc100))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${qty(i.quantity)}× ${i.productName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sm(c: C.zinc700),
                  ),
                ),
                Text(brl(i.total), style: T.sm(w: T.medium)),
              ],
            ),
          ),
        const SizedBox(height: 10),
        BillSummary(bill: bill),
        if (guests != null && guests > 1) KV('Por pessoa ($guests)', brl(bill.total / guests)),
      ],
      footer: app.terminal.canPrint && items.isNotEmpty
          ? BtnRow(
              Btn('Fechar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
              Btn('Imprimir', icon: Icons.print_outlined, onTap: () => Navigator.pop(context, 'print')),
            )
          : Btn('Fechar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
    );
  }
}

/// Resumo da conta (itens, couvert, desconto, taxa, total, pago, restante).
class BillSummary extends StatelessWidget {
  const BillSummary({super.key, required this.bill, this.totalLabel = 'Total'});
  final SessionBill bill;
  final String totalLabel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      KV('Itens', brl(bill.itemsSubtotal)),
      if (bill.couvertAmount > 0.005) KV('Couvert', '+ ${brl(bill.couvertAmount)}'),
      if (bill.discount > 0.005) KV('Desconto', '- ${brl(bill.discount)}'),
      if (bill.serviceFee > 0.005) KV('Taxa de serviço (${percent(bill.serviceFeePercentage)}%)', '+ ${brl(bill.serviceFee)}'),
      KV(totalLabel, brl(bill.total), strong: true),
      if (bill.paid > 0.005) ...[
        KV('Pago', brl(bill.paid), color: C.emerald600),
        KV('Restante', brl(bill.remaining), color: C.zinc700),
      ],
    ],
  );
}

// ── Cancelar item ────────────────────────────────────────────────────────────

/// Motivo do cancelamento de um item. Fecha devolvendo o motivo.
class CancelItemSheet extends StatefulWidget {
  const CancelItemSheet({super.key, required this.item});
  final SessionItem item;

  @override
  State<CancelItemSheet> createState() => _CancelItemSheetState();
}

class _CancelItemSheetState extends State<CancelItemSheet> {
  static const _reasons = ['Pedido errado', 'Cliente desistiu', 'Produto indisponível', 'Demora excessiva', 'Outro'];
  String _selected = '';
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _reason => _selected == 'Outro' ? _custom.text.trim() : _selected;

  @override
  Widget build(BuildContext context) => SheetBody(
    padding: 24,
    children: [
      Text('Cancelar item', style: T.base(w: T.bold)),
      const SizedBox(height: 2),
      Text('${widget.item.productName} × ${qty(widget.item.quantity)}', style: T.sm(c: C.zinc500)),
      const SizedBox(height: 14),
      Text('MOTIVO', style: T.label),
      const SizedBox(height: 8),
      for (final r in _reasons)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tap(
            onTap: () => setState(() => _selected = r),
            color: _selected == r ? C.red50 : C.white,
            border: BorderSide(color: _selected == r ? C.red400 : C.zinc200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(r, style: T.sm(c: _selected == r ? C.red700 : C.zinc700)),
            ),
          ),
        ),
      if (_selected == 'Outro')
        Field(
          controller: _custom,
          hint: 'Descreva o motivo...',
          maxLength: 255,
          focus: C.red400,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
    ],
    footer: BtnRow(
      Btn('Voltar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
      Btn('Confirmar', kind: BtnKind.danger, onTap: _reason.isEmpty ? null : () => Navigator.pop(context, _reason)),
    ),
  );
}

// ── Transferir mesa ──────────────────────────────────────────────────────────

/// Escolhe a mesa LIVRE de destino e transfere a sessão inteira.
class TransferTableSheet extends StatefulWidget {
  const TransferTableSheet({super.key});

  @override
  State<TransferTableSheet> createState() => _TransferTableSheetState();
}

class _TransferTableSheetState extends State<TransferTableSheet> {
  String? _selected;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_selected == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await app.session.transferTable(_selected!);
    if (!mounted) return;
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
    final currentId = app.session.session?.tableId;
    final free = app.tables.tables.where((t) => t.status == 'available' && !t.isComanda && t.id != currentId).toList()
      ..sort((a, b) => naturalCompare(a.number, b.number));
    return SheetBody(
      title: 'Transferir mesa',
      subtitle: 'Escolha a mesa livre de destino.',
      children: [
        if (free.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('Nenhuma mesa livre no momento.', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          )
        else
          ColGrid(
            cols: 3,
            children: [
              for (final t in free) Choice(t.title, selected: _selected == t.id, onTap: () => setState(() => _selected = t.id)),
            ],
          ),
        const SizedBox(height: 10),
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Cancelar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(_busy ? 'Transferindo...' : 'Transferir', loading: _busy, onTap: _selected == null ? null : _confirm),
      ),
    );
  }
}

// ── Couvert ──────────────────────────────────────────────────────────────────

/// Couvert artístico: valor POR PESSOA × pessoas. Mesa sem comandas lança na
/// mesa; com comandas, informa as pessoas de cada comanda.
class CouvertSheet extends StatefulWidget {
  const CouvertSheet({super.key, required this.session, this.comandas});
  final SessionDetail session;

  /// Comandas `open` (mesa com comandas) ou `null` (couvert da mesa).
  final List<Comanda>? comandas;

  @override
  State<CouvertSheet> createState() => _CouvertSheetState();
}

class _CouvertSheetState extends State<CouvertSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _persons;
  late final Map<String, TextEditingController> _perComanda;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    final current = s.couvert;
    final firstComandaCouvert = widget.comandas?.map((c) => c.couvert).whereType<SessionCouvert>().firstOrNull;
    final amount = current?.amount ?? firstComandaCouvert?.amount ?? s.couvertDefaultAmount;
    _amount = TextEditingController(text: amount != null && amount > 0 ? decimalInput(amount) : '');
    _persons = TextEditingController(text: '${current?.persons ?? s.guestCount ?? 1}');
    _perComanda = {
      for (final c in widget.comandas ?? const <Comanda>[])
        c.id: TextEditingController(text: c.couvert != null ? '${c.couvert!.persons}' : ''),
    };
  }

  @override
  void dispose() {
    _amount.dispose();
    _persons.dispose();
    for (final c in _perComanda.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  void _confirm() {
    final amount = parseDecimal(_amount.text);
    if (amount <= 0) {
      setState(() => _error = 'Informe o valor por pessoa.');
      return;
    }
    if (widget.comandas != null) {
      final list = <({String id, int persons})>[
        for (final e in _perComanda.entries)
          if ((int.tryParse(e.value.text.trim()) ?? 0) > 0) (id: e.key, persons: int.parse(e.value.text.trim())),
      ];
      if (list.isEmpty) {
        setState(() => _error = 'Informe as pessoas de ao menos uma comanda.');
        return;
      }
      _run(() => app.session.setComandaCouvert(amount, list));
    } else {
      final persons = int.tryParse(_persons.text.trim()) ?? 0;
      if (persons < 1 || persons > 100) {
        setState(() => _error = 'Informe o número de pessoas (1 a 100).');
        return;
      }
      _run(() => app.session.setCouvert(amount, persons));
    }
  }

  static final _digits = [FilteringTextInputFormatter.digitsOnly];

  @override
  Widget build(BuildContext context) {
    final byComanda = widget.comandas != null;
    final amount = parseDecimal(_amount.text);
    final persons = byComanda
        ? _perComanda.values.fold<int>(0, (a, c) => a + (int.tryParse(c.text.trim()) ?? 0))
        : (int.tryParse(_persons.text.trim()) ?? 0);
    final canRemove = app.auth.permissions.couvertRemove;
    return SheetBody(
      title: 'Couvert artístico',
      subtitle: 'Valor por pessoa × número de pessoas.',
      children: [
        MoneyField(label: 'Valor por pessoa (R\$)', controller: _amount, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        if (!byComanda)
          Field(
            label: 'Pessoas',
            controller: _persons,
            keyboard: TextInputType.number,
            formatters: _digits,
            maxLength: 3,
            large: true,
            onChanged: (_) => setState(() {}),
          )
        else ...[
          Text('PESSOAS POR COMANDA', style: T.label),
          const SizedBox(height: 6),
          if (widget.comandas!.isEmpty) Text('Nenhuma comanda aberta nesta mesa.', style: T.xs(c: C.amber600)),
          for (final c in widget.comandas!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Comanda ${c.label}', style: T.sm(w: T.medium)),
                        if (c.couvert != null)
                          Text('Lançado: ${c.couvert!.persons} × ${brl(c.couvert!.amount)}', style: T.xs(c: C.zinc400)),
                      ],
                    ),
                  ),
                  if (c.couvert != null && canRemove)
                    GestureDetector(
                      onTap: _busy ? null : () => _run(() => app.session.removeComandaCouvert(c.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Remover', style: T.xs(w: T.semibold, c: C.red500)),
                      ),
                    ),
                  SizedBox(
                    width: 76,
                    child: Field(
                      controller: _perComanda[c.id]!,
                      hint: '0',
                      keyboard: TextInputType.number,
                      formatters: _digits,
                      maxLength: 2,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.zinc50, borderRadius: BorderRadius.circular(12)),
          child: KV('Total do couvert', brl(amount * persons), strong: true),
        ),
        const SizedBox(height: 10),
        if (!byComanda && widget.session.couvert != null && canRemove)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Btn('Remover couvert', kind: BtnKind.dangerSoft, dense: true, onTap: _busy ? null : () => _run(app.session.removeCouvert)),
          ),
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Cancelar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(_busy ? 'Salvando...' : 'Lançar', loading: _busy, onTap: _confirm),
      ),
    );
  }
}

// ── Cancelar mesa ────────────────────────────────────────────────────────────

class CancelSessionSheet extends StatefulWidget {
  const CancelSessionSheet({super.key, required this.session});
  final SessionDetail session;

  @override
  State<CancelSessionSheet> createState() => _CancelSessionSheetState();
}

class _CancelSessionSheetState extends State<CancelSessionSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _needsPassword => widget.session.requireCancelSessionPassword;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await app.session.cancelSession(
      override: _needsPassword ? ManagerOverride(_email.text, _password.text) : null,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      _password.clear();
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_needsPassword || (_email.text.trim().isNotEmpty && _password.text.isNotEmpty);
    return SheetBody(
      title: 'Cancelar mesa?',
      children: [
        Text(
          'Toda a comanda de ${widget.session.title} será cancelada. Esta ação não pode ser desfeita.',
          textAlign: TextAlign.center,
          style: T.sm(c: C.zinc500),
        ),
        const SizedBox(height: 12),
        if (_needsPassword) ...[
          OverrideFields(
            email: _email,
            password: _password,
            title: 'A loja exige senha para cancelar a mesa',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(_busy ? 'Cancelando...' : 'Cancelar mesa', kind: BtnKind.danger, loading: _busy, onTap: ready ? _confirm : null),
      ),
    );
  }
}

/// Converte a exceção da API em texto para `toast` (uso pontual nas telas).
String apiMessage(Object e) => e is ApiException ? e.message : 'Não foi possível concluir a operação.';
