import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/addon_rules.dart';
import '../../core/uuid.dart';
import '../../models/models.dart';
import '../catalog.dart';
import '../kit.dart';

/// Detalhe do produto: sabores (pizza), grupos do combo, adicionais, peso ou
/// quantidade e observação. Fecha devolvendo o [CartItem] montado.
/// Espelha `ProductDetailModal.vue`.
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.product});
  final MenuProduct product;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  MenuProduct get p => widget.product;

  late double _quantity = p.allowFractionalQty ? 0 : 1;
  final _weight = TextEditingController();
  final _notes = TextEditingController();
  final _search = <String, String>{};

  /// grupo → adicional → quantidade.
  final _addons = <String, Map<String, int>>{};
  final _flavors = <String>{};

  /// grupo do combo → itens escolhidos.
  final _combo = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    for (final g in p.comboGroups) {
      final defaults = g.items.where((i) => i.isDefault).map((i) => i.id).toSet();
      if (defaults.isNotEmpty) _combo[g.id] = defaults;
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ── Adicionais ────────────────────────────────────────────────────────────

  int _groupCount(String groupId) => (_addons[groupId]?.values ?? const <int>[]).fold(0, (a, b) => a + b);
  int _addonQty(String groupId, String itemId) => _addons[groupId]?[itemId] ?? 0;

  void _toggleAddon(AddonGroup g, AddonItem item) => setState(() {
    final current = _addons.putIfAbsent(g.id, () => {});
    if (current.containsKey(item.id)) {
      current.remove(item.id);
    } else if (g.max == 1) {
      current
        ..clear()
        ..[item.id] = 1;
    } else if (hasRoom(g, _groupCount(g.id))) {
      current[item.id] = 1;
    }
  });

  void _incAddon(AddonGroup g, AddonItem item) {
    if (!canIncrement(g, item, _addonQty(g.id, item.id), _groupCount(g.id))) return;
    setState(() => _addons.putIfAbsent(g.id, () => {}).update(item.id, (v) => v + 1, ifAbsent: () => 1));
  }

  void _decAddon(AddonGroup g, AddonItem item) => setState(() {
    final current = _addons[g.id];
    final q = current?[item.id] ?? 0;
    if (q <= 1) {
      current?.remove(item.id);
    } else {
      current![item.id] = q - 1;
    }
  });

  List<AddonChoice> _buildAddons() => [
    for (final items in _addons.values)
      for (final e in items.entries)
        if (e.value > 0) AddonChoice(e.key, e.value),
  ];

  // ── Pizza / combo ─────────────────────────────────────────────────────────

  void _toggleFlavor(String id) => setState(() {
    final max = p.pizza!.maxFlavors;
    if (_flavors.contains(id)) {
      _flavors.remove(id);
    } else if (_flavors.length < max) {
      _flavors.add(id);
    } else if (max == 1) {
      _flavors
        ..clear()
        ..add(id);
    }
  });

  void _toggleCombo(ComboGroup g, ComboGroupItem item) => setState(() {
    final current = _combo.putIfAbsent(g.id, () => {});
    if (current.contains(item.id)) {
      current.remove(item.id);
    } else if (g.max == 1) {
      current
        ..clear()
        ..add(item.id);
    } else if (current.length < g.max) {
      current.add(item.id);
    }
  });

  double get _comboExtra {
    var extra = 0.0;
    for (final g in p.comboGroups) {
      for (final id in _combo[g.id] ?? const <String>{}) {
        extra += g.items.where((i) => i.id == id).firstOrNull?.extraPrice ?? 0;
      }
    }
    return extra;
  }

  // ── Preço e validação ─────────────────────────────────────────────────────

  double get _unitPrice =>
      (p.type == 'pizza' ? pizzaPrice(p, _flavors) : p.price) + addonsExtra(p.addonGroups, _buildAddons()) + _comboExtra;

  String? get _blockReason {
    if (p.pizza != null && _flavors.isEmpty) return 'Escolha ao menos 1 sabor';
    final comboOk = p.comboGroups.every((g) => !g.isRequired || (_combo[g.id]?.length ?? 0) >= g.min);
    if (!comboOk) return 'Selecione as opções obrigatórias do combo';
    final counts = {for (final g in p.addonGroups) g.id: _groupCount(g.id)};
    if (!addonsSatisfied(p.addonGroups, counts)) return requiredAddonsMessage;
    if (p.allowFractionalQty && _quantity <= 0) return 'Informe o peso do produto';
    return null;
  }

  void _confirm() {
    if (_blockReason != null) return;
    final combos = <ComboSelection>[
      for (final g in p.comboGroups)
        if ((_combo[g.id] ?? const <String>{}).isNotEmpty)
          ComboSelection(
            groupId: g.id,
            groupName: g.name,
            items: [
              for (final id in _combo[g.id]!)
                () {
                  final it = g.items.where((i) => i.id == id).firstOrNull;
                  return (id: it?.productId ?? id, name: it?.name ?? '');
                }(),
            ],
          ),
    ];
    Navigator.pop(
      context,
      CartItem(
        localId: uuidV7(),
        product: p,
        quantity: _quantity,
        notes: _notes.text.trim(),
        addons: _buildAddons(),
        selectedFlavorIds: _flavors.toList(),
        comboSelections: combos,
        unitPrice: _unitPrice,
      ),
    );
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  bool _matches(String name, String key) {
    final q = fold((_search[key] ?? '').trim());
    return q.isEmpty || fold(name).contains(q);
  }

  Widget _group({
    required String title,
    required String hint,
    required String searchKey,
    required String searchHint,
    required int total,
    required List<Widget> rows,
    required String emptyText,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: C.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: C.zinc200),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.zinc100))),
          child: Row(
            children: [
              Expanded(child: Text(title, style: T.xs(w: T.semibold, c: C.zinc700))),
              if (hint.isNotEmpty) Text(hint, style: T.xs(c: C.zinc400)),
            ],
          ),
        ),
        // Busca só em grupo grande (mais de 6 opções).
        if (total > 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _search[searchKey] = v),
              style: T.sm(),
              decoration: fieldDecoration(hint: searchHint, fill: C.zinc50),
            ),
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(emptyText, textAlign: TextAlign.center, style: T.xs(c: C.zinc400)),
          ),
        ...rows,
      ],
    ),
  );

  Widget _radioRow({
    required bool selected,
    required String name,
    required VoidCallback onTap,
    String? price,
    String? imageUrl,
  }) => Tap(
    onTap: onTap,
    color: selected ? C.primary50 : C.white,
    radius: 0,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? C.secondary500 : Colors.transparent,
            border: Border.all(color: selected ? C.secondary500 : C.zinc300, width: 2),
          ),
          child: selected
              ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.white, shape: BoxShape.circle))
              : null,
        ),
        const SizedBox(width: 12),
        if (imageUrl != null) ...[ProductThumb(imageUrl, size: 32, radius: 6), const SizedBox(width: 10)],
        Expanded(child: Text(name, style: T.sm())),
        if (price != null) Text(price, style: T.xs(w: T.semibold, c: C.secondary600)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final block = _blockReason;
    final pizza = p.pizza;
    return Scaffold(
      backgroundColor: C.zinc50,
      body: Column(
        children: [
          AppHeader(
            title: p.name,
            onBack: () => Navigator.pop(context),
            actions: [
              if (p.type != 'simple')
                Pill(p.type == 'pizza' ? 'Pizza' : 'Combo', bg: C.secondary100, fg: C.secondary700, size: 12, bold: false),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (pizza != null)
                  _group(
                    title: pizza.groupName,
                    hint: 'Até ${pizza.maxFlavors} sabor(es) · Obrigatório',
                    searchKey: 'flavors',
                    searchHint: 'Buscar sabor...',
                    total: pizza.flavors.length,
                    emptyText: 'Nenhum sabor encontrado',
                    rows: [
                      for (final f in pizza.flavors.where((f) => _matches(f.name, 'flavors')))
                        _radioRow(
                          selected: _flavors.contains(f.id),
                          name: f.name,
                          imageUrl: f.imageUrl,
                          price: f.price > 0 ? brl(f.price) : null,
                          onTap: () => _toggleFlavor(f.id),
                        ),
                    ],
                  ),
                for (final g in p.comboGroups)
                  _group(
                    title: g.name,
                    hint: '${g.isRequired ? 'Obrigatório · ' : ''}${g.max == 1 ? 'Escolha 1' : 'Até ${g.max}'}',
                    searchKey: g.id,
                    searchHint: 'Buscar item...',
                    total: g.items.length,
                    emptyText: 'Nenhum item encontrado',
                    rows: [
                      for (final i in g.items.where((i) => _matches(i.name, g.id)))
                        _radioRow(
                          selected: _combo[g.id]?.contains(i.id) ?? false,
                          name: i.name,
                          price: i.extraPrice > 0 ? '+${brl(i.extraPrice)}' : null,
                          onTap: () => _toggleCombo(g, i),
                        ),
                    ],
                  ),
                for (final g in p.addonGroups)
                  _group(
                    title: g.name,
                    hint: groupLabel(g),
                    searchKey: g.id,
                    searchHint: 'Buscar adicional...',
                    total: g.items.length,
                    emptyText: 'Nenhum adicional encontrado',
                    rows: [
                      for (final i in g.items.where((i) => _matches(i.name, g.id)))
                        if (itemLimit(g, i) > 1)
                          Container(
                            color: _addonQty(g.id, i.id) > 0 ? C.primary50 : C.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(i.name, style: T.sm())),
                                if (i.price > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Text('+${brl(i.price)}', style: T.xs(w: T.semibold, c: C.secondary600)),
                                  ),
                                Stepper2(
                                  value: '${_addonQty(g.id, i.id)}',
                                  onMinus: _addonQty(g.id, i.id) > 0 ? () => _decAddon(g, i) : null,
                                  onPlus: canIncrement(g, i, _addonQty(g.id, i.id), _groupCount(g.id))
                                      ? () => _incAddon(g, i)
                                      : null,
                                ),
                              ],
                            ),
                          )
                        else
                          _radioRow(
                            selected: _addonQty(g.id, i.id) > 0,
                            name: i.name,
                            price: i.price > 0 ? '+${brl(i.price)}' : null,
                            onTap: () => _toggleAddon(g, i),
                          ),
                    ],
                  ),
                if (p.allowFractionalQty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Peso / quantidade (${p.unitOfMeasure ?? 'kg'})', style: T.xs(w: T.medium, c: C.zinc600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _weight,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                          style: T.base(),
                          decoration: fieldDecoration(hint: 'Ex.: 0,350'),
                          onChanged: (v) => setState(() {
                            final parsed = parseDecimal(v);
                            _quantity = parsed > 0 ? (parsed * 1000).round() / 1000 : 0;
                          }),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Stepper2(
                          size: 38,
                          value: qty(_quantity),
                          onMinus: _quantity > 1 ? () => setState(() => _quantity -= 1) : null,
                          onPlus: _quantity < 99 ? () => setState(() => _quantity += 1) : null,
                        ),
                        const Spacer(),
                        Text('${brl(_unitPrice)} un.', style: T.xs(c: C.zinc500)),
                      ],
                    ),
                  ),
                Field(controller: _notes, hint: 'Observações (opcional)', maxLength: 255),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: C.white, border: Border(top: BorderSide(color: C.zinc200))),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: SizedBox(
              width: double.infinity,
              child: block != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: C.zinc300, borderRadius: BorderRadius.circular(12)),
                      child: Text(block, textAlign: TextAlign.center, style: T.sm(w: T.semibold, c: C.white)),
                    )
                  : Btn('Adicionar ao pedido — ${brl(_unitPrice * _quantity)}', kind: BtnKind.accent, onTap: _confirm),
            ),
          ),
        ],
      ),
    );
  }
}
