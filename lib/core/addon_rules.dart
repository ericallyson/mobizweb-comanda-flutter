/// Regras de adicional — a mesma regra do PDV web, do PWA
/// (`lib/addonRules.ts`) e do servidor. O cardápio já manda, por grupo,
/// `is_required`, `min` e `max` resolvidos com os overrides do produto:
///  - mínimo só é exigido quando o grupo é obrigatório;
///  - máximo 0 = sem limite;
///  - contagem do grupo = soma das quantidades dos adicionais escolhidos;
///  - limite por adicional: repetir desligado → `max_quantity` (default 1);
///    ligado → máximo do grupo (máximo 0 → teto de 99).
library;

import '../models/models.dart';

const requiredAddonsMessage = 'Selecione os adicionais obrigatórios';

/// Teto por adicional com a repetição ligada e grupo sem máximo.
const repeatCap = 99;

bool isGroupRequired(AddonGroup g) => g.isRequiredFlag ?? g.min > 0;

bool isGroupSatisfied(AddonGroup g, int count) => !isGroupRequired(g) || count >= g.min;

/// Ainda cabe mais um adicional no grupo?
bool hasRoom(AddonGroup g, int count) => g.max <= 0 || count < g.max;

/// Todos os grupos obrigatórios atingiram o mínimo?
bool addonsSatisfied(List<AddonGroup> groups, Map<String, int> counts) =>
    groups.every((g) => isGroupSatisfied(g, counts[g.id] ?? 0));

/// "Obrigatório · Escolha até N" ('' = sem rótulo).
String groupLabel(AddonGroup g) => [
  if (isGroupRequired(g)) 'Obrigatório',
  if (g.max > 0) 'Escolha até ${g.max}',
].join(' · ');

/// Quantas vezes o mesmo adicional pode ser escolhido.
int itemLimit(AddonGroup g, AddonItem item) {
  final limit = item.itemLimit;
  if (limit != null && limit >= 1) return limit;
  if (g.allowRepeat) return g.max > 0 ? g.max : repeatCap;
  final max = item.maxQuantity ?? 1;
  return max < 1 ? 1 : max;
}

bool canIncrement(AddonGroup g, AddonItem item, int itemQty, int groupCount) =>
    itemQty < itemLimit(g, item) && hasRoom(g, groupCount);

/// Σ extra × quantidade dos adicionais escolhidos.
double addonsExtra(List<AddonGroup> groups, List<AddonChoice> addons) {
  var sum = 0.0;
  for (final a in addons) {
    for (final g in groups) {
      final item = g.items.where((i) => i.id == a.addonGroupItemId).firstOrNull;
      if (item != null) {
        sum += item.price * a.quantity;
        break;
      }
    }
  }
  return sum;
}

/// Preço da pizza pelos sabores: `average` = média; senão o MAIOR.
double pizzaPrice(MenuProduct p, Set<String> flavorIds) {
  final pizza = p.pizza;
  if (pizza == null || flavorIds.isEmpty) return p.price;
  final prices = pizza.flavors.where((f) => flavorIds.contains(f.id)).map((f) => f.price).toList();
  if (prices.isEmpty) return p.price;
  if (pizza.pricingRule == 'average') return prices.reduce((a, b) => a + b) / prices.length;
  return prices.reduce((a, b) => a > b ? a : b);
}

/// Rótulo de preço na lista: pizza sem preço base mostra "a partir de".
({bool from, double value}) listPrice(MenuProduct p) {
  if (p.type == 'pizza') {
    final prices = (p.pizza?.flavors ?? const <FlavorItem>[]).map((f) => f.price).where((v) => v > 0).toList();
    if (prices.isNotEmpty) {
      final min = prices.reduce((a, b) => a < b ? a : b);
      return (p.price > 0 && p.price < min) ? (from: false, value: p.price) : (from: true, value: min);
    }
  }
  return (from: false, value: p.price);
}
