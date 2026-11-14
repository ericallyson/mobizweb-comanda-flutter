import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../kit.dart';
import '../printing.dart';

/// Caixa (seção 5.8 do layout novo): abertura, suprimento/sangria, detalhes e
/// fechamento. É uma ABA da [HomeShell] (sem `Scaffold` próprio nem "voltar").
/// As rotinas são as mesmas de antes ([CashStore]); exige conexão.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key, this.allowed = true});

  /// O operador tem alguma permissão de caixa (abrir, fechar ou movimentar)?
  /// Sem nenhuma, a aba só explica isso e não consulta o servidor.
  final bool allowed;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _opening = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.cash.addListener(_changed);
    if (widget.allowed) app.cash.load();
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
      toast(context, 'Caixa aberto');
    }
  }

  Future<void> _reload() async {
    await app.cash.load();
    if (mounted && app.cash.error == null) toast(context, 'Caixa atualizado');
  }

  Future<void> _movement(String type) async {
    final done = await showSheet<bool>(context, (_) => _MovementSheet(type: type));
    if (done == true && mounted) toast(context, type == 'supply' ? 'Suprimento registrado' : 'Sangria registrada');
  }

  Future<void> _showDetails() => showSheet<void>(context, (_) => const _DetailsSheet());

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
    toast(context, 'Caixa fechado');
    if (app.settings.printCashClose && app.terminal.canPrint) {
      await printCashClose(context, detail: detail, counted: counted, showExpected: reveal);
    }
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.all(14),
    child: CardBox(
      padding: 24,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: T.body(c: C.sub),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cash = app.cash;
    final ctx = cash.context;
    final session = cash.session;

    Widget body;
    if (!widget.allowed) {
      body = _message('Seu usuário não tem permissão para operar o caixa.');
    } else if (cash.loading && ctx == null) {
      body = const StateView(text: 'Carregando caixa...');
    } else if (ctx == null) {
      body = StateView(text: cash.error ?? 'Não foi possível carregar o caixa.', error: true, onAction: cash.load);
    } else if (!ctx.enabled) {
      body = _message('A operação de caixa pelo PDV não está habilitada para esta loja.');
    } else if (session == null) {
      body = _openForm(ctx);
    } else {
      body = _openSession(ctx, session);
    }

    return ColoredBox(
      color: C.bg,
      child: Column(
        children: [
          AppHeader(
            title: 'Caixa',
            subtitle: app.auth.store?.name,
            actions: [
              if (widget.allowed)
                HeaderButton.text('Atualizar', spinning: cash.loading, onTap: cash.loading ? null : _reload),
            ],
          ),
          if (cash.error != null && ctx != null) Note(cash.error!, kind: NoteKind.error, radius: 0),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _openForm(CashContext ctx) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      if (!ctx.canOpen)
        CardBox(
          padding: 24,
          child: Text(
            'Nenhum caixa aberto. Você não tem permissão para abrir o caixa.',
            textAlign: TextAlign.center,
            style: T.body(c: C.sub),
          ),
        )
      else
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Abrir caixa',
                style: T.s(17, w: T.bold, c: C.ink, h: 1.25),
              ),
              const SizedBox(height: 2),
              Text('Informe o valor inicial (fundo de troco).', style: T.s(13, c: C.sub, h: 1.35)),
              const SizedBox(height: 14),
              MoneyField(label: 'Valor de abertura (R\$)', controller: _opening),
              const SizedBox(height: 12),
              Field(label: 'Observações', controller: _notes, hint: 'Opcional', maxLength: 255),
              const SizedBox(height: 16),
              ErrText(_error),
              Btn(_busy ? 'Abrindo...' : 'Abrir caixa', kind: BtnKind.navy, loading: _busy, onTap: _open),
            ],
          ),
        ),
    ],
  );

  Widget _openSession(CashContext ctx, CashSession session) {
    final summary = app.cash.detail?.summary;

    Widget stat(String label, num? value, [Color color = C.ink]) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.s(11.5, c: C.sub, h: 1.3),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(brl(value), maxLines: 1, style: T.num(17, c: color)),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Só status e data: o sistema não tem hoje um "total em caixa" único
        // (o esperado vem por forma de pagamento), e não se cria cálculo novo.
        HeroCard(
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: C.mint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Caixa aberto · ${dateTimeIso(session.openedAt)}',
                  style: T.num(13, w: T.medium, c: C.white, h: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!ctx.canSeeFinancial)
          CardBox(
            child: Text('Valores ocultos para o seu perfil.', style: T.body(c: C.sub, size: 13)),
          )
        else
          ColGrid(
            cols: 2,
            children: [
              stat('Abertura', session.openingAmount),
              stat('Vendas', summary?.ordersTotal),
              stat('Suprimentos e entradas', summary?.totalCashIn, C.greenText),
              stat('Sangrias e saídas', summary?.totalCashOut, C.orangeText),
            ],
          ),
        const SizedBox(height: 12),
        ColGrid(
          cols: 2,
          children: [
            if (ctx.canMove) Btn('Suprimento', kind: BtnKind.green, onTap: () => _movement('supply')),
            if (ctx.canMove) Btn('Sangria', kind: BtnKind.orange, onTap: () => _movement('withdrawal')),
            Btn('Ver detalhes', kind: BtnKind.secondary, onTap: _showDetails),
            if (ctx.canClose) Btn('Fechar caixa', kind: BtnKind.navy, onTap: _close),
          ],
        ),
      ],
    );
  }
}

/// "Ver detalhes": abertura, totais por tipo de movimento, recebimentos por
/// forma e a lista de movimentações. Os mesmos dados que a tela antiga abria
/// no lugar; agora numa janela por baixo.
class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet();

  @override
  Widget build(BuildContext context) {
    final ctx = app.cash.context;
    final session = app.cash.session;
    final summary = app.cash.detail?.summary;
    final movements = app.cash.detail?.movements ?? const <CashMovement>[];
    final financial = ctx?.canSeeFinancial ?? false;
    final byType = summary?.movementsByType ?? const <String, double?>{};

    const types = [
      ('supply', 'Suprimentos', true),
      ('cash_in', 'Entradas', true),
      ('withdrawal', 'Sangrias', false),
      ('cash_out', 'Saídas e devoluções', false),
    ];

    Widget line(String title, String? detail, String value, {Color color = C.ink, bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.body(w: T.semibold)),
                if (detail != null && detail.isNotEmpty) Text(detail, style: T.s(12, c: C.sub, h: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(value, style: T.num(13.5, c: color)),
        ],
      ),
    );

    Widget block(List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CardBox(
        color: C.bg,
        padding: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: rows),
        ),
      ),
    );

    return SheetBody(
      title: 'Detalhes do caixa',
      subtitle: session == null ? null : 'Aberto em ${dateTimeIso(session.openedAt)}',
      children: [
        if (!financial)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Valores ocultos para o seu perfil.', style: T.body(c: C.sub, size: 13)),
          )
        else ...[
          block([
            line('Abertura', null, brl(session?.openingAmount)),
            line('Vendas', null, brl(summary?.ordersTotal), last: byType.isEmpty),
            for (final (i, (type, label, credit)) in types.indexed)
              if (byType.containsKey(type))
                line(
                  label,
                  null,
                  brl(byType[type]),
                  color: credit ? C.greenText : C.orangeText,
                  last: i == types.length - 1,
                ),
          ]),
          if (summary != null && summary.paymentsByMethod.isNotEmpty) ...[
            const SectionLabel('Recebimentos por forma'),
            block([
              for (final (i, pm) in summary.paymentsByMethod.indexed)
                line(
                  pm.label,
                  pm.count == 1 ? '1 recebimento' : '${pm.count} recebimentos',
                  brl(pm.total),
                  last: i == summary.paymentsByMethod.length - 1,
                ),
            ]),
          ],
        ],
        const SectionLabel('Movimentações'),
        if (movements.isEmpty)
          Text('Nenhum suprimento ou sangria.', style: T.body(c: C.sub, size: 13))
        else
          block([
            for (final (i, m) in movements.indexed)
              line(
                m.label,
                m.reason,
                financial ? brl(m.amount) : '',
                color: m.isCredit ? C.greenText : C.orangeText,
                last: i == movements.length - 1,
              ),
          ]),
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
    final focus = _supply ? C.green : C.orange;
    return SheetBody(
      title: _supply ? 'Suprimento' : 'Sangria',
      subtitle: _supply
          ? 'Entrada de dinheiro no caixa (troco, fundo).'
          : 'Retirada de dinheiro do caixa (depósito, despesa).',
      children: [
        MoneyField(
          label: 'Valor (R\$)',
          controller: _amount,
          focus: focus,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
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
        Btn('Cancelar', kind: BtnKind.secondary, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(
          _busy ? 'Salvando...' : (_supply ? 'Confirmar suprimento' : 'Confirmar sangria'),
          kind: _supply ? BtnKind.green : BtnKind.orange,
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
      title: 'Fechar caixa',
      subtitle: reveal
          ? 'Confira os valores calculados por forma de pagamento.'
          : 'Conte o caixa e informe os valores por forma de pagamento.',
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.label, style: T.body(w: T.semibold, size: 13)),
                    ),
                    if (reveal && e.total != null)
                      Text(
                        'esperado ${brl(e.total)}',
                        style: T.num(12, w: T.medium, c: C.sub),
                      ),
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
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              _line('Total contado', brl(counted), C.ink, bold: true),
              if (reveal) _line('Esperado', brl(expected), C.sub),
              if (reveal) _line('Diferença', brl(diff), diff == 0 ? C.greenText : C.cancel, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ErrText(_error),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.secondary, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(_busy ? 'Fechando...' : 'Fechar caixa', kind: BtnKind.navy, loading: _busy, onTap: _confirm),
      ),
    );
  }

  Widget _line(String k, String v, Color color, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(k, style: T.body(c: color, size: 13.5)),
        ),
        Text(
          v,
          style: T.num(13.5, w: bold ? T.bold : T.medium, c: color),
        ),
      ],
    ),
  );
}
