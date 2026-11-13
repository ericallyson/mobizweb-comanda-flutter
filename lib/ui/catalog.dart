import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/addon_rules.dart';
import '../models/models.dart';
import 'kit.dart';

/// Ícone da categoria: o nome salvo em `categories.icon` (lucide, no PWA)
/// resolvido para o equivalente do Material.
const _categoryIcons = <String, IconData>{
  'pizza': Icons.local_pizza_outlined,
  'sandwich': Icons.lunch_dining_outlined,
  'salad': Icons.eco_outlined,
  'soup': Icons.soup_kitchen_outlined,
  'beef': Icons.kebab_dining_outlined,
  'fish': Icons.set_meal_outlined,
  'drumstick': Icons.kebab_dining_outlined,
  'utensils': Icons.restaurant,
  'chef-hat': Icons.restaurant_menu,
  'coffee': Icons.coffee_outlined,
  'cup-soda': Icons.local_drink_outlined,
  'beer': Icons.sports_bar_outlined,
  'wine': Icons.wine_bar_outlined,
  'martini': Icons.local_bar_outlined,
  'glass-water': Icons.water_drop_outlined,
  'milk': Icons.local_cafe_outlined,
  'ice-cream-cone': Icons.icecream_outlined,
  'dessert': Icons.cake_outlined,
  'cake': Icons.cake_outlined,
  'cookie': Icons.cookie_outlined,
  'croissant': Icons.bakery_dining_outlined,
  'candy': Icons.cookie_outlined,
  'grape': Icons.spa_outlined,
  'package': Icons.inventory_2_outlined,
};

/// URL da imagem: o servidor pode mandar caminho relativo (`/storage/…`).
String? resolveImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${app.api.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
}

class ProductThumb extends StatelessWidget {
  const ProductThumb(this.url, {super.key, this.size = 44, this.radius = 8});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveImageUrl(url);
    if (resolved == null) return const SizedBox.shrink();
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decodifica no tamanho exibido: economiza memória no terminal.
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, _, _) => Container(width: size, height: size, color: C.zinc100),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : Container(width: size, height: size, color: C.zinc100),
      ),
    );
  }
}

/// Navegação do cardápio: categoria raiz → subcategorias → produtos, com
/// busca. Espelha `CatalogBrowser.vue`.
class CatalogBrowser extends StatefulWidget {
  const CatalogBrowser({super.key, this.channel = 'table', required this.onSelect});
  final String channel;
  final ValueChanged<MenuProduct> onSelect;

  @override
  State<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends State<CatalogBrowser> {
  final _search = TextEditingController();
  static const _noCategory = '__sem_categoria__';
  List<String> _navIds = [];

  @override
  void initState() {
    super.initState();
    app.menu.addListener(_changed);
    app.menu.fetch(widget.channel);
  }

  @override
  void dispose() {
    app.menu.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<MenuCategory> get _stack {
    final out = <MenuCategory>[];
    for (final id in _navIds) {
      final cat = app.menu.categories.where((c) => (c.id ?? _noCategory) == id).firstOrNull;
      if (cat == null) break;
      out.add(cat);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final menu = app.menu;
    final stack = _stack;
    final current = stack.isEmpty ? null : stack.last;
    final atRoot = current == null;
    final q = fold(_search.text.trim());
    final searching = q.isNotEmpty;

    final subcategories = atRoot
        ? menu.categories.where((c) => c.parentId == null).toList()
        : (current.id == null ? <MenuCategory>[] : menu.categories.where((c) => c.parentId == current.id).toList());

    final products = (searching
            ? menu.categories.expand((c) => c.products).where((p) => fold(p.name).contains(q))
            : (atRoot ? const <MenuProduct>[] : current.products))
        .where((p) => p.isAvailable)
        .toList();

    Widget body;
    if (menu.loading && menu.categories.isEmpty) {
      body = const StateView(text: 'Carregando cardápio...');
    } else if (menu.error != null && menu.categories.isEmpty) {
      body = StateView(text: menu.error!, error: true, onAction: menu.refresh);
    } else {
      final tiles = <Widget>[
        if (!searching && !atRoot)
          Tap(
            onTap: () => setState(() => _navIds = _navIds.sublist(0, stack.length - 1)),
            color: C.secondary500,
            radius: 0,
            splash: Colors.white24,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, size: 18, color: C.white),
                const SizedBox(width: 8),
                Expanded(child: Text(current.name, style: T.sm(w: T.semibold, c: C.white))),
              ],
            ),
          ),
        if (!searching)
          for (final cat in subcategories)
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x33FFFFFF)))),
              child: Tap(
                onTap: () => setState(() => _navIds = [...stack.map((c) => c.id ?? _noCategory), cat.id ?? _noCategory]),
                color: C.primary600,
                radius: 0,
                splash: Colors.white24,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    if (_categoryIcons[cat.icon] != null) ...[
                      Icon(_categoryIcons[cat.icon], size: 18, color: C.white.withValues(alpha: 0.9)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(w: T.medium, c: C.white)),
                    ),
                    Icon(Icons.chevron_right, size: 22, color: C.white.withValues(alpha: 0.8)),
                  ],
                ),
              ),
            ),
        for (final p in products) _ProductTile(product: p, onTap: () => widget.onSelect(p)),
      ];

      if (tiles.isEmpty || (searching && products.isEmpty) || (!searching && !atRoot && subcategories.isEmpty && products.isEmpty)) {
        final msg = searching
            ? 'Nenhum produto encontrado.'
            : atRoot
            ? 'Nenhuma categoria disponível.'
            : 'Nenhum item nesta categoria.';
        tiles.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 56),
          child: Text(msg, textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
        ));
      }
      body = ListView.builder(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: tiles.length,
        itemBuilder: (_, i) => tiles[i],
      );
    }

    return Container(
      color: C.zinc50,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(color: C.white, border: Border(bottom: BorderSide(color: C.zinc200))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: T.sm(),
              decoration: fieldDecoration(
                hint: 'Buscar produto...',
                fill: C.zinc50,
                suffix: _search.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () => setState(_search.clear),
                        child: const Icon(Icons.close, size: 18, color: C.zinc400),
                      ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final MenuProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = listPrice(product);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.zinc100))),
      child: Tap(
        onTap: onTap,
        color: C.white,
        radius: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            if (product.imageUrl != null) ...[ProductThumb(product.imageUrl), const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.sm(w: T.medium)),
                  if (product.type != 'simple')
                    Text(product.type == 'pizza' ? 'Pizza' : 'Combo', style: T.xs(w: T.medium, c: C.secondary500)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              price.from ? 'a partir de\n${brl(price.value)}' : brl(price.value),
              textAlign: TextAlign.right,
              style: T.s(price.from ? 12 : 14, w: T.bold, c: C.primary700, h: 1.25),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 22, color: C.zinc300),
          ],
        ),
      ),
    );
  }
}
