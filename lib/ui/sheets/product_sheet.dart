import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/addon_rules.dart';
import '../../core/product_builder.dart';
import '../../models/models.dart';
import '../kit.dart';
import '../order_widgets.dart';

/// Abre a janela certa para o produto e devolve o item montado (`null` se o
/// garçom desistiu):
///  - pizza, combo ou adicional obrigatório: montagem em abas (5.3 do plano);
///  - os demais: quantidade (ou peso), adicionais opcionais e observação.
///
/// As regras são as de [ProductBuilder], as mesmas da tela antiga do produto.
Future<CartItem?> showProductSheet(BuildContext context, MenuProduct product) => showSheet<CartItem>(
  context,
  (_) => needsBuilder(product) ? _BuilderSheet(product: product) : _ItemSheet(product: product),
);

// ── Peças comuns às duas janelas ─────────────────────────────────────────────

/// Rótulo de seção com algo à direita ("ESCOLHA ATÉ 2 SABORES … OBRIGATÓRIO").
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.left, [this.right = '']);
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(left.toUpperCase(), style: T.section)),
        if (right.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(right.toUpperCase(), style: T.section),
          ),
      ],
    ),
  );
}

/// Linha de opção com marcação (quadrada = várias; redonda = uma só), nome e
/// preço. Desabilitada, fica apagada e não responde ao toque.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.name,
    required this.selected,
    required this.single,
    this.price,
    this.imageUrl,
    this.onTap,
  });
  final String name;
  final bool selected;

  /// Escolha única (marcação redonda).
  final bool single;
  final String? price;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    checked: single ? null : selected,
    selected: single ? selected : null,
    child: InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 47),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? C.magenta : C.white,
                  shape: single ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: single ? null : BorderRadius.circular(4),
                  border: Border.all(color: selected ? C.magenta : const Color(0xFFB4B6D0), width: 1.5),
                ),
                child: !selected
                    ? null
                    : single
                    ? const Center(
                        child: SizedBox(
                          width: 7,
                          height: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: C.white, shape: BoxShape.circle),
                          ),
                        ),
                      )
                    : const Icon(Icons.check, size: 14, color: C.white),
              ),
              const SizedBox(width: 10),
              if (resolveImageUrl(imageUrl) != null) ...[
                ProductThumb(url: imageUrl, name: name, size: 32, radius: 6),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(name, style: T.body(w: T.semibold)),
              ),
              if (price != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    price!,
                    style: T.num(13, w: FontWeight.w400, c: C.sub),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Campo de observação (o mesmo de sempre, até 255 caracteres).
class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller, required this.hint, required this.lines});
  final TextEditingController controller;
  final String hint;
  final int lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _GroupLabel('Observações (opcional)'),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        inputFormatters: [LengthLimitingTextInputFormatter(255)],
        textCapitalization: TextCapitalization.sentences,
        style: T.body(w: T.medium),
        decoration: fieldDecoration(hint: hint, focus: C.magenta),
      ),
    ],
  );
}

/// Campo de peso do produto vendido por peso.
class _WeightField extends StatelessWidget {
  const _WeightField({required this.controller, required this.unit, required this.onChanged, this.autofocus = false});
  final TextEditingController controller;
  final String unit;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _GroupLabel('Peso / quantidade ($unit)'),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: T.s(16, w: T.semibold, c: C.ink, h: 1.3),
        decoration: fieldDecoration(hint: 'Ex.: 0,350', focus: C.magenta),
        onChanged: onChanged,
      ),
    ],
  );
}

/// Busca dentro de um grupo grande (mais de 6 opções), como na tela antiga.
class _GroupSearch extends StatelessWidget {
  const _GroupSearch({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: TextField(
      onChanged: onChanged,
      autocorrect: false,
      style: T.body(w: T.medium),
      decoration: fieldDecoration(hint: hint, focus: C.magenta),
    ),
  );
}

/// As seções de um grupo de adicional: rótulo, busca (grupo grande) e as
/// opções com marcação ou contador.
List<Widget> _addonGroupSection(
  ProductBuilder b,
  AddonGroup g, {
  required String query,
  required ValueChanged<String> onQuery,
}) {
  final q = fold(query.trim());
  final items = g.items.where((i) => q.isEmpty || fold(i.name).contains(q)).toList();
  return [
    _GroupLabel(g.name, groupLabel(g)),
    if (g.items.length > 6) _GroupSearch(hint: 'Buscar adicional...', onChanged: onQuery),
    if (items.isEmpty) const _EmptyGroup('Nenhum adicional encontrado'),
    for (final i in items)
      if (itemLimit(g, i) > 1)
        Container(
          constraints: const BoxConstraints(minHeight: 47),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(i.name, style: T.body(w: T.semibold)),
              ),
              if (i.price > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '+ ${brl(i.price)}',
                    style: T.num(13, w: FontWeight.w400, c: C.sub),
                  ),
                ),
              QtyStepper(
                value: '${b.addonQty(g.id, i.id)}',
                onMinus: b.addonQty(g.id, i.id) > 0 ? () => b.decAddon(g, i) : null,
                onPlus: b.canIncAddon(g, i) ? () => b.incAddon(g, i) : null,
              ),
            ],
          ),
        )
      else
        _OptionRow(
          name: i.name,
          selected: b.addonQty(g.id, i.id) > 0,
          single: g.max == 1,
          price: i.price > 0 ? '+ ${brl(i.price)}' : null,
          onTap: b.canToggleAddon(g, i) ? () => b.toggleAddon(g, i) : null,
        ),
  ];
}

class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: T.s(12.5, c: C.sub),
    ),
  );
}

/// Motivo do bloqueio, logo acima do rodapé.
class _BlockText extends StatelessWidget {
  const _BlockText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: T.s(12.5, w: T.semibold, c: C.orangeText, h: 1.3),
    ),
  );
}

// ── Montagem em abas (pizza, combo, adicional obrigatório) ───────────────────

enum _Step { flavors, combo, addons, summary }

class _BuilderSheet extends StatefulWidget {
  const _BuilderSheet({required this.product});
  final MenuProduct product;

  @override
  State<_BuilderSheet> createState() => _BuilderSheetState();
}

class _BuilderSheetState extends State<_BuilderSheet> {
  late final ProductBuilder _b = ProductBuilder(widget.product)..addListener(_changed);
  final _notes = TextEditingController();
  final _weight = TextEditingController();
  final _search = <String, String>{};
  late final List<_Step> _steps = [
    if (p.pizza != null) _Step.flavors,
    if (p.comboGroups.isNotEmpty) _Step.combo,
    if (p.addonGroups.isNotEmpty) _Step.addons,
    _Step.summary,
  ];
  int _tab = 0;

  MenuProduct get p => widget.product;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _b.dispose();
    _notes.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ── Abas ──────────────────────────────────────────────────────────────────

  String _label(_Step step) => switch (step) {
    _Step.flavors => 'Sabores',
    _Step.combo => 'Opções',
    // Um grupo só: a aba leva o nome dele ("Borda"). Vários: "Adicionais".
    _Step.addons => p.addonGroups.length == 1 ? p.addonGroups.first.name : 'Adicionais',
    _Step.summary => 'Resumo',
  };

  /// Contador verde da aba: quantas escolhas já foram feitas nela.
  int _count(_Step step) => switch (step) {
    _Step.flavors => _b.flavors.length,
    _Step.combo => _b.comboCount,
    _Step.addons => _b.addonsCount,
    _Step.summary => 0,
  };

  /// O que falta nesta aba para seguir adiante (`null` = nada).
  String? _blockOf(_Step step) => switch (step) {
    _Step.flavors => _b.flavorsBlock,
    _Step.combo => _b.comboBlock,
    _Step.addons => _b.addonsBlock,
    _Step.summary => _b.blockReason,
  };

  /// Só dá para pular para uma aba quando as anteriores estão completas.
  bool _canOpen(int index) => _steps.take(index).every((s) => _blockOf(s) == null);

  void _next() {
    if (_blockOf(_steps[_tab]) != null) return;
    if (_tab < _steps.length - 1) {
      FocusScope.of(context).unfocus();
      setState(() => _tab += 1);
      return;
    }
    _b.notes = _notes.text;
    final item = _b.build();
    if (item != null) Navigator.pop(context, item);
  }

  Widget _tabs() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        for (final (i, step) in _steps.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == _tab,
              enabled: _canOpen(i),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _canOpen(i)
                    ? () {
                        FocusScope.of(context).unfocus();
                        setState(() => _tab = i);
                      }
                    : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _tab ? C.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == _tab
                        ? const [BoxShadow(color: Color(0x1A05061F), blurRadius: 3, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _label(step),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.s(12.5, w: T.bold, c: i == _tab ? C.ink : C.sub, h: 1.2),
                        ),
                      ),
                      if (_count(step) > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(8)),
                          child: Text('${_count(step)}', style: T.num(10.5, c: const Color(0xFF04301F), h: 1.3)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ── Conteúdo de cada aba ──────────────────────────────────────────────────

  bool _matches(String name, String key) {
    final q = fold((_search[key] ?? '').trim());
    return q.isEmpty || fold(name).contains(q);
  }

  List<Widget> _flavorsTab() {
    final pizza = p.pizza!;
    final max = pizza.maxFlavors;
    final shown = pizza.flavors.where((f) => _matches(f.name, 'flavors')).toList();
    return [
      _GroupLabel(max == 1 ? 'Escolha 1 sabor' : 'Escolha até $max sabores', 'obrigatório'),
      if (pizza.flavors.length > 6)
        _GroupSearch(hint: 'Buscar sabor...', onChanged: (v) => setState(() => _search['flavors'] = v)),
      if (shown.isEmpty) const _EmptyGroup('Nenhum sabor encontrado'),
      for (final f in shown)
        _OptionRow(
          name: f.name,
          selected: _b.flavors.contains(f.id),
          single: max == 1,
          imageUrl: f.imageUrl,
          price: f.price > 0 ? brl(f.price) : null,
          onTap: _b.canToggleFlavor(f.id) ? () => _b.toggleFlavor(f.id) : null,
        ),
    ];
  }

  List<Widget> _comboTab() => [
    for (final g in p.comboGroups) ...[
      _GroupLabel(g.name, '${g.isRequired ? 'Obrigatório · ' : ''}${g.max == 1 ? 'Escolha 1' : 'Até ${g.max}'}'),
      if (g.items.length > 6) _GroupSearch(hint: 'Buscar item...', onChanged: (v) => setState(() => _search[g.id] = v)),
      if (g.items.where((i) => _matches(i.name, g.id)).isEmpty) const _EmptyGroup('Nenhum item encontrado'),
      for (final i in g.items.where((i) => _matches(i.name, g.id)))
        _OptionRow(
          name: i.name,
          selected: _b.comboChoice(g.id).contains(i.id),
          single: g.max == 1,
          price: i.extraPrice > 0 ? '+ ${brl(i.extraPrice)}' : null,
          onTap: _b.canToggleCombo(g, i) ? () => _b.toggleCombo(g, i) : null,
        ),
    ],
  ];

  List<Widget> _addonsTab() => [
    for (final g in p.addonGroups)
      ..._addonGroupSection(_b, g, query: _search[g.id] ?? '', onQuery: (v) => setState(() => _search[g.id] = v)),
  ];

  List<Widget> _summaryTab() {
    Widget line(String title, String? sub, {bool last = false}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: C.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: T.body(w: T.semibold)),
          if (sub != null && sub.isNotEmpty) Text(sub, style: T.s(12, c: C.sub, h: 1.35)),
        ],
      ),
    );

    final groups = [..._b.comboSummary, ..._b.addonSummary];
    return [
      const SizedBox(height: 4),
      CardBox(
        color: C.bg,
        padding: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              line(p.name, p.pizza == null ? null : _b.flavorNames.join(' / '), last: groups.isEmpty),
              for (final (i, g) in groups.indexed) line(g.group, g.items, last: i == groups.length - 1),
            ],
          ),
        ),
      ),
      if (p.allowFractionalQty)
        _WeightField(controller: _weight, unit: p.unitOfMeasure ?? 'kg', onChanged: _b.setWeight)
      else
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Quantidade', style: T.body(w: T.semibold)),
              ),
              QtyStepper(
                value: qty(_b.quantity),
                onMinus: _b.canDecrement ? _b.decQuantity : null,
                onPlus: _b.canIncrementQuantity ? _b.incQuantity : null,
              ),
            ],
          ),
        ),
      _NotesField(controller: _notes, hint: p.pizza != null ? 'Ex.: bem assada' : 'Ex.: sem cebola', lines: 2),
    ];
  }

  /// Total do item. Pizza ainda sem sabor mostra o "a partir de" da lista
  /// (`listPrice`), porque o preço vem dos sabores.
  String get _totalText {
    if (_b.flavorsBlock != null) {
      final from = listPrice(p);
      return from.from ? 'a partir de ${brl(from.value)}' : brl(from.value);
    }
    return brl(_b.total > 0 ? _b.total : _b.unitPrice);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_tab];
    final block = _blockOf(step);
    final last = _tab == _steps.length - 1;
    return SizedBox(
      // Altura fixa: a janela não pula de tamanho ao trocar de aba.
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: SheetBody(
        title: p.name,
        top: _tabs(),
        fill: true,
        footerLine: true,
        children: switch (step) {
          _Step.flavors => _flavorsTab(),
          _Step.combo => _comboTab(),
          _Step.addons => _addonsTab(),
          _Step.summary => _summaryTab(),
        },
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (block != null) _BlockText(block),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total do item', style: T.s(11, c: C.sub, h: 1.3)),
                      Text(_totalText, style: T.num(15)),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 124),
                  child: Btn(
                    last ? 'Adicionar' : 'Continuar',
                    kind: BtnKind.magenta,
                    onTap: block == null ? _next : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quantidade e observação (produto simples ou por peso) ────────────────────

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.product});
  final MenuProduct product;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final ProductBuilder _b = ProductBuilder(widget.product)..addListener(_changed);
  final _notes = TextEditingController();
  final _weight = TextEditingController();
  final _search = <String, String>{};

  MenuProduct get p => widget.product;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _b.dispose();
    _notes.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _confirm() {
    _b.notes = _notes.text;
    final item = _b.build();
    if (item != null) Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final block = _b.blockReason;
    final unit = p.unitOfMeasure ?? 'kg';
    return SheetBody(
      title: p.name,
      subtitle: p.allowFractionalQty ? '${brl(_b.unitPrice)} por $unit' : brl(_b.unitPrice),
      trailing: p.allowFractionalQty
          ? null
          : QtyStepper(
              value: qty(_b.quantity),
              onMinus: _b.canDecrement ? _b.decQuantity : null,
              onPlus: _b.canIncrementQuantity ? _b.incQuantity : null,
            ),
      children: [
        if (p.allowFractionalQty)
          _WeightField(controller: _weight, unit: unit, onChanged: _b.setWeight, autofocus: true),
        for (final g in p.addonGroups)
          ..._addonGroupSection(_b, g, query: _search[g.id] ?? '', onQuery: (v) => setState(() => _search[g.id] = v)),
        _NotesField(controller: _notes, hint: 'Ex.: sem gelo', lines: 3),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (block != null) _BlockText(block),
          Row(
            children: [
              Expanded(
                child: Btn('Cancelar', kind: BtnKind.secondary, onTap: () => Navigator.pop(context)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Btn(
                  'Adicionar · ${brl(_b.total)}',
                  kind: BtnKind.magenta,
                  onTap: block == null ? _confirm : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
