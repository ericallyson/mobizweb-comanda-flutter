import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../kit.dart';
import '../printing.dart';

/// Caixa: abertura, suprimento/sangria, detalhes e fechamento. Espelha
/// `CashView.vue`. Exige conexão (sem fila offline).
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _opening = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  bool _details = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.cash.addListener(_changed);
    app.cash.load();
  }

  @override
  void dispose() {
    app.cash.removeListener(_changed);
    _opening.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes = _notes.text.trim();
    final error = await app.cash.open(parseDecimal(_opening.text), notes: notes.isEmpty ? null : notes);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      _opening.clear();
      _notes.clear();
      toast(context, 'Caixa aberto.');
    }
  }

  Future<void> _movement(String type) async {
    final done = await showSheet<bool>(context, (_) => _MovementSheet(type: type));
    if (done == true && mounted) toast(context, type == 'supply' ? 'Suprimento registrado.' : 'Sangria registrada.');
  }

  Future<void> _close() async {
    final session = app.cash.session;
    if (session == null) return;
    // Recarrega o esperado no momento do fechamento.
    final detail = await app.cash.fetchSummary(session.id);
    if (!mounted) return;
    if (detail == null) {
      toast(context, app.cash.error ?? 'Não foi possível carregar os detalhes do caixa.', error: true);
      return;
    }
    final ctx = app.cash.context!;
    final reveal = !ctx.blindClose && ctx.canSeeFinancial;
    final counted = await showSheet<Map<String, double>>(
      context,
      (_) => _CloseSheet(detail: detail, revealExpected: reveal),
      dismissible: false,
    );
    if (counted == null || !mounted) return;
    toast(context, 'Caixa fechado.');
    if (app.settings.printCashClose && app.terminal.canPrint) {
      await printCashClose(context, detail: detail, counted: counted, showExpected: reveal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cash = app.cash;
    final ctx = cash.context;
    final session = cash.session;

    Widget body;
    if (cash.loading && ctx == null) {
      body = const StateView(text: 'Carregando caixa...');
    } else if (ctx == null) {
      body = StateView(text: cash.error ?? 'Não foi possível carregar o caixa.', error: true, onAction: cash.load);
    } else if (!ctx.enabled) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: CardBox(
          padding: 24,
          child: Text(
            'A operação de caixa pelo PDV não está habilitada para esta loja.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: C.zinc500, height: 1.43),
          ),
        ),
      );
    } else if (session == null) {
      body = _openForm(ctx);
    } else {
      body = _openSession(ctx, session);
    }

    return Scaffold(
      backgroundColor: C.zinc50,
      body: Column(
        children: [
          AppHeader(
            title: 'Caixa',
            subtitle: app.auth.store?.name,
            onBack: () => Navigator.pop(context),
            actions: [
              HeaderButton(icon: Icons.refresh, tooltip: 'Atualizar', spinning: cash.loading, onTap: cash.loading ? null : cash.load),
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _openForm(CashContext ctx) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (!ctx.canOpen)
        const CardBox(
          padding: 24,
          child: Text(
            'Nenhum caixa aberto. Você não tem permissão para abrir o caixa.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: C.zinc500, height: 1.43),
          ),
        )
      else
        CardBox(
          padding: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Abrir caixa', style: T.base(w: T.bold)),
              const SizedBox(height: 2),
              Text('Informe o valor inicial (fundo de troco).', style: T.sm(c: C.zinc500)),
              const SizedBox(height: 16),
              MoneyField(label: 'Valor de abertura (R\$)', controller: _opening),
              const SizedBox(height: 14),
              Field(label: 'Observações', controller: _notes, hint: 'Opcional', maxLength: 255),
              const SizedBox(height: 14),
              ErrText(_error),
              Btn(_busy ? 'Abrindo...' : 'Abrir caixa', loading: _busy, onTap: _open),
            ],
          ),
        ),
    ],
  );

  Widget _openSession(CashContext ctx, CashSession session) {
    final summary = app.cash.detail?.summary;
    final movements = app.cash.detail?.movements ?? const <CashMovement>[];
    final financial = ctx.canSeeFinancial;

    const rows = [
      ('supply', 'Suprimentos', true),
      ('cash_in', 'Entradas', true),
      ('withdrawal', 'Sangrias', false),
      ('cash_out', 'Saídas/devoluções', false),
    ];
    final byType = summary?.movementsByType ?? const <String, double?>{};

    Widget stat(String label, String value, [Color color = C.zinc800]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.xs(c: C.zinc400)),
        Text(value, style: T.sm(w: T.semibold, c: color)),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: C.emerald100, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.emerald500, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Caixa aberto', style: T.xs(w: T.semibold, c: C.emerald700)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(dateTimeIso(session.openedAt), style: T.xs(c: C.zinc400)),
                ],
              ),
              const SizedBox(height: 14),
              if (!financial)
                Text('Valores ocultos para o seu perfil.', style: T.xs(c: C.zinc400))
              else
                ColGrid(
                  cols: 2,
                  gap: 12,
                  children: [
                    stat('Abertura', brl(session.openingAmount)),
                    stat('Vendas', brl(summary?.ordersTotal)),
                    if (byType.isEmpty) ...[
                      stat('Suprimentos e entradas', brl(summary?.totalCashIn), C.emerald600),
                      stat('Sangrias e saídas', brl(summary?.totalCashOut), C.amber600),
                    ] else
                      for (final (type, label, credit) in rows)
                        stat(label, brl(byType[type]), credit ? C.emerald600 : C.amber600),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ColGrid(
          cols: 2,
          gap: 12,
          children: [
            if (ctx.canMove) Btn('Suprimento', kind: BtnKind.success, onTap: () => _movement('supply')),
            if (ctx.canMove) Btn('Sangria', kind: BtnKind.warn, onTap: () => _movement('withdrawal')),
            Btn(_details ? 'Ocultar detalhes' : 'Ver detalhes', kind: BtnKind.outline, onTap: () => setState(() => _details = !_details)),
            if (ctx.canClose) Btn('Fechar caixa', onTap: _close),
          ],
        ),
        if (_details) ...[
          if (financial && summary != null && summary.paymentsByMethod.isNotEmpty) ...[
            const SizedBox(height: 14),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Recebimentos por forma', style: T.sm(w: T.bold)),
                  const SizedBox(height: 10),
                  for (final pm in summary.paymentsByMethod)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: pm.label,
                                children: [TextSpan(text: ' (${pm.count})', style: T.xs(c: C.zinc400))],
                              ),
                              style: T.sm(c: C.zinc600),
                            ),
                          ),
                          Text(brl(pm.total), style: T.sm(w: T.medium, c: C.zinc600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Movimentações', style: T.sm(w: T.bold)),
                const SizedBox(height: 10),
                if (movements.isEmpty) Text('Nenhum suprimento ou sangria.', style: T.sm(c: C.zinc400)),
                for (final m in movements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.label, style: T.sm(w: T.medium, c: m.isCredit ? C.emerald600 : C.amber600)),
                              if (m.reason != null) Text(m.reason!, style: T.xs(c: C.zinc400)),
                            ],
                          ),
                        ),
                        Text(brl(m.amount), style: T.sm(w: T.medium, c: C.zinc700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Suprimento (entrada) ou sangria (retirada) de dinheiro.
class _MovementSheet extends StatefulWidget {
  const _MovementSheet({required this.type});
  final String type;

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _supply => widget.type == 'supply';
  bool get _valid => parseDecimal(_amount.text) > 0 && _reason.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await app.cash.movement(widget.type, parseDecimal(_amount.text), _reason.text.trim());
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
    final focus = _supply ? C.emerald500 : C.amber500;
    return SheetBody(
      padding: 24,
      children: [
        Text(_supply ? 'Suprimento' : 'Sangria', style: T.base(w: T.bold)),
        const SizedBox(height: 2),
        Text(
          _supply ? 'Entrada de dinheiro no caixa (troco, fundo).' : 'Retirada de dinheiro do caixa (depósito, despesa).',
          style: T.sm(c: C.zinc500),
        ),
        const SizedBox(height: 16),
        MoneyField(label: 'Valor (R\$)', controller: _amount, focus: focus, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        Field(
          label: 'Motivo',
          controller: _reason,
          hint: 'Descreva o motivo...',
          maxLength: 255,
          focus: focus,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ErrText(_error),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(
          _busy ? 'Salvando...' : 'Confirmar',
          kind: _supply ? BtnKind.success : BtnKind.warn,
          loading: _busy,
          onTap: _valid ? _confirm : null,
        ),
      ),
    );
  }
}

/// Fechamento do caixa: valor contado por forma de pagamento. No fechamento
/// cego o esperado não aparece. Fecha devolvendo o mapa contado.
class _CloseSheet extends StatefulWidget {
  const _CloseSheet({required this.detail, required this.revealExpected});
  final CashDetail detail;
  final bool revealExpected;

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  late final Map<String, TextEditingController> _values = {
    for (final e in widget.detail.summary.expectedBreakdown)
      e.key: TextEditingController(text: widget.revealExpected && e.total != null ? decimalInput(e.total!) : ''),
  };
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Map<String, double> get _parsed => {for (final e in _values.entries) e.key: round2(parseDecimal(e.value.text))};

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final counted = _parsed;
    final error = await app.cash.close(counted, notes: _notes.text.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, counted);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.detail.summary.expectedBreakdown;
    final reveal = widget.revealExpected;
    final counted = _parsed.values.fold<double>(0, (a, b) => a + b);
    final expected = entries.fold<double>(0, (a, e) => a + (e.total ?? 0));
    final diff = round2(counted - expected);
    return SheetBody(
      padding: 24,
      children: [
        Text('Fechar caixa', style: T.base(w: T.bold)),
        const SizedBox(height: 2),
        Text(
          reveal
              ? 'Confira os valores calculados por forma de pagamento.'
              : 'Conte o caixa e informe os valores por forma de pagamento.',
          style: T.sm(c: C.zinc500),
        ),
        const SizedBox(height: 14),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.label, style: T.sm(w: T.medium, c: C.zinc700))),
                    if (reveal && e.total != null) Text('esperado ${brl(e.total)}', style: T.xs(c: C.zinc400)),
                  ],
                ),
                const SizedBox(height: 4),
                MoneyField(
                  controller: _values[e.key]!,
                  enabled: !(e.isDigital && reveal),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        Field(label: 'Observações', controller: _notes, hint: 'Opcional', maxLength: 500, maxLines: 2),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.zinc50, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _line('Total contado', brl(counted), C.zinc600, bold: true),
              if (reveal) _line('Esperado', brl(expected), C.zinc600),
              if (reveal) _line('Diferença', brl(diff), diff == 0 ? C.emerald600 : C.red600, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ErrText(_error),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(_busy ? 'Fechando...' : 'Fechar caixa', loading: _busy, onTap: _confirm),
      ),
    );
  }

  Widget _line(String k, String v, Color color, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(k, style: T.sm(c: color))),
        Text(v, style: T.sm(w: bold ? T.semibold : FontWeight.w400, c: color)),
      ],
    ),
  );
}
