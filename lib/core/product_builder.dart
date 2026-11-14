/// Montagem de um item do pedido: sabores (pizza), grupos do combo,
/// adicionais, peso ou quantidade e observação.
///
/// É a lógica que morava na tela cheia do produto (`ProductScreen`, espelho
/// de `ProductDetailModal.vue` do PWA), agora sem tela: a janela de montagem
/// e a janela de quantidade/observação usam este mesmo controlador. As regras
/// continuam em `addon_rules.dart` e no cardápio; aqui nada é recalculado de
/// outro jeito.
library;

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'addon_rules.dart';
import 'format.dart';
import 'uuid.dart';

/// Textos de bloqueio (os mesmos da tela antiga do produto).
const flavorRequiredMessage = 'Escolha ao menos 1 sabor';
const comboRequiredMessage = 'Selecione as opções obrigatórias do combo';
const weightRequiredMessage = 'Informe o peso do produto';

/// Quantidade máxima por linha do pedido.
const maxLineQuantity = 99;

/// O "+" do cardápio não pode lançar direto: pizza, combo ou produto com
/// grupo de adicional obrigatório precisam da janela de montagem.
bool needsBuilder(MenuProduct p) => p.pizza != null || p.comboGroups.isNotEmpty || p.addonGroups.any(isGroupRequired);

class ProductBuilder extends ChangeNotifier {
  ProductBuilder(this.product) : quantity = product.allowFractionalQty ? 0 : 1 {
    for (final g in product.comboGroups) {
      final defaults = g.items.where((i) => i.isDefault).map((i) => i.id).toSet();
      if (defaults.isNotEmpty) _combo[g.id] = defaults;
    }
  }

  final MenuProduct product;

  /// Unidades, ou o peso quando o produto é vendido por peso.
  double quantity;
  String notes = '';

  /// grupo → adicional → quantidade.
  final _addons = <String, Map<String, int>>{};
  final _flavors = <String>{};

  /// grupo do combo → itens escolhidos.
  final _combo = <String, Set<String>>{};

  // ── Quantidade ────────────────────────────────────────────────────────────

  bool get canDecrement => !product.allowFractionalQty && quantity > 1;
  bool get canIncrementQuantity => !product.allowFractionalQty && quantity < maxLineQuantity;

  void incQuantity() {
    if (!canIncrementQuantity) return;
    quantity += 1;
    notifyListeners();
  }

  void decQuantity() {
    if (!canDecrement) return;
    quantity -= 1;
    notifyListeners();
  }

  /// Peso digitado ("0,350"): três casas; vazio ou inválido = 0.
  void setWeight(String raw) {
    final parsed = parseDecimal(raw);
    quantity = parsed > 0 ? (parsed * 1000).round() / 1000 : 0;
    notifyListeners();
  }

  // ── Adicionais ────────────────────────────────────────────────────────────

  int groupCount(String groupId) => (_addons[groupId]?.values ?? const <int>[]).fold(0, (a, b) => a + b);
  int addonQty(String groupId, String itemId) => _addons[groupId]?[itemId] ?? 0;

  /// Total de adicionais escolhidos em todos os grupos.
  int get addonsCount => product.addonGroups.fold(0, (a, g) => a + groupCount(g.id));

  void toggleAddon(AddonGroup g, AddonItem item) {
    final current = _addons.putIfAbsent(g.id, () => {});
    if (current.containsKey(item.id)) {
      current.remove(item.id);
    } else if (g.max == 1) {
      current
        ..clear()
        ..[item.id] = 1;
    } else if (hasRoom(g, groupCount(g.id))) {
      current[item.id] = 1;
    }
    notifyListeners();
  }

  /// O adicional pode ser marcado agora? (marcado sempre pode desmarcar;
  /// grupo de escolha única troca a escolha).
  bool canToggleAddon(AddonGroup g, AddonItem item) =>
      addonQty(g.id, item.id) > 0 || g.max == 1 || hasRoom(g, groupCount(g.id));

  bool canIncAddon(AddonGroup g, AddonItem item) => canIncrement(g, item, addonQty(g.id, item.id), groupCount(g.id));

  void incAddon(AddonGroup g, AddonItem item) {
    if (!canIncAddon(g, item)) return;
    _addons.putIfAbsent(g.id, () => {}).update(item.id, (v) => v + 1, ifAbsent: () => 1);
    notifyListeners();
  }

  void decAddon(AddonGroup g, AddonItem item) {
    final current = _addons[g.id];
    final q = current?[item.id] ?? 0;
    if (q <= 1) {
      current?.remove(item.id);
    } else {
      current![item.id] = q - 1;
    }
    notifyListeners();
  }

  List<AddonChoice> buildAddons() => [
    for (final items in _addons.values)
      for (final e in items.entries)
        if (e.value > 0) AddonChoice(e.key, e.value),
  ];

  // ── Pizza / combo ─────────────────────────────────────────────────────────

  Set<String> get flavors => _flavors;
  int get maxFlavors => product.pizza?.maxFlavors ?? 0;

  /// O sabor pode ser marcado agora? No limite, os demais ficam desabilitados
  /// (com limite 1, o toque troca o sabor).
  bool canToggleFlavor(String id) => _flavors.contains(id) || _flavors.length < maxFlavors || maxFlavors == 1;

  void toggleFlavor(String id) {
    final max = product.pizza!.maxFlavors;
    if (_flavors.contains(id)) {
      _flavors.remove(id);
    } else if (_flavors.length < max) {
      _flavors.add(id);
    } else if (max == 1) {
      _flavors
        ..clear()
        ..add(id);
    }
    notifyListeners();
  }

  Set<String> comboChoice(String groupId) => _combo[groupId] ?? const <String>{};

  /// Total de itens escolhidos nos grupos do combo.
  int get comboCount => product.comboGroups.fold(0, (a, g) => a + comboChoice(g.id).length);

  bool canToggleCombo(ComboGroup g, ComboGroupItem item) =>
      comboChoice(g.id).contains(item.id) || g.max == 1 || comboChoice(g.id).length < g.max;

  void toggleCombo(ComboGroup g, ComboGroupItem item) {
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
    notifyListeners();
  }

  double get comboExtra {
    var extra = 0.0;
    for (final g in product.comboGroups) {
      for (final id in comboChoice(g.id)) {
        extra += g.items.where((i) => i.id == id).firstOrNull?.extraPrice ?? 0;
      }
    }
    return extra;
  }

  // ── Preço e validação ─────────────────────────────────────────────────────

  double get unitPrice =>
      (product.type == 'pizza' ? pizzaPrice(product, _flavors) : product.price) +
      addonsExtra(product.addonGroups, buildAddons()) +
      comboExtra;

  double get total => unitPrice * quantity;

  /// Falta escolher sabor (só pizza).
  String? get flavorsBlock => product.pizza != null && _flavors.isEmpty ? flavorRequiredMessage : null;

  /// Falta alguma opção obrigatória do combo.
  String? get comboBlock => product.comboGroups.every((g) => !g.isRequired || comboChoice(g.id).length >= g.min)
      ? null
      : comboRequiredMessage;

  /// Falta algum adicional obrigatório.
  String? get addonsBlock {
    final counts = {for (final g in product.addonGroups) g.id: groupCount(g.id)};
    return addonsSatisfied(product.addonGroups, counts) ? null : requiredAddonsMessage;
  }

  /// Por que o item ainda não pode ser adicionado (`null` = pode). Mesma
  /// ordem de checagem da tela antiga.
  String? get blockReason =>
      flavorsBlock ??
      comboBlock ??
      addonsBlock ??
      (product.allowFractionalQty && quantity <= 0 ? weightRequiredMessage : null);

  // ── Resumo ────────────────────────────────────────────────────────────────

  List<String> get flavorNames => [
    for (final f in product.pizza?.flavors ?? const <FlavorItem>[])
      if (_flavors.contains(f.id)) f.name,
  ];

  /// "Grupo: item, item" de cada grupo do combo com escolha.
  List<({String group, String items})> get comboSummary => [
    for (final g in product.comboGroups)
      if (comboChoice(g.id).isNotEmpty)
        (group: g.name, items: g.items.where((i) => comboChoice(g.id).contains(i.id)).map((i) => i.name).join(', ')),
  ];

  /// "Grupo: 2× item, item" de cada grupo de adicional com escolha.
  List<({String group, String items})> get addonSummary => [
    for (final g in product.addonGroups)
      if (groupCount(g.id) > 0)
        (
          group: g.name,
          items: g.items
              .where((i) => addonQty(g.id, i.id) > 0)
              .map((i) => addonQty(g.id, i.id) > 1 ? '${addonQty(g.id, i.id)}× ${i.name}' : i.name)
              .join(', '),
        ),
  ];

  // ── Resultado ─────────────────────────────────────────────────────────────

  /// O item pronto para o carrinho, ou `null` enquanto houver bloqueio.
  CartItem? build() {
    if (blockReason != null) return null;
    final combos = <ComboSelection>[
      for (final g in product.comboGroups)
        if (comboChoice(g.id).isNotEmpty)
          ComboSelection(
            groupId: g.id,
            groupName: g.name,
            items: [
              for (final id in comboChoice(g.id))
                () {
                  final it = g.items.where((i) => i.id == id).firstOrNull;
                  return (id: it?.productId ?? id, name: it?.name ?? '');
                }(),
            ],
          ),
    ];
    return CartItem(
      localId: uuidV7(),
      product: product,
      quantity: quantity,
      notes: notes.trim(),
      addons: buildAddons(),
      selectedFlavorIds: _flavors.toList(),
      comboSelections: combos,
      unitPrice: unitPrice,
    );
  }
}
