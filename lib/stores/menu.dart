import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/storage.dart';
import '../models/models.dart';

/// Remove categorias repetidas (a API às vezes devolve o mesmo nome várias
/// vezes): agrupa por id — ou por nome quando o id vem vazio — e mescla os
/// produtos sem duplicar.
List<MenuCategory> dedupeCategories(List<MenuCategory> list) {
  final byKey = <String, MenuCategory>{};
  for (final cat in list) {
    final key = cat.id ?? 'name:${cat.name.trim().toLowerCase()}';
    final existing = byKey[key];
    if (existing != null) {
      final seen = existing.products.map((p) => p.id).toSet();
      for (final p in cat.products) {
        if (seen.add(p.id)) existing.products.add(p);
      }
    } else {
      byKey[key] = MenuCategory(
        id: cat.id,
        name: cat.name,
        icon: cat.icon,
        parentId: cat.parentId,
        products: [...cat.products],
      );
    }
  }
  return byKey.values.toList();
}

/// Cardápio da loja. A mesa usa o canal `table`; o balcão, `pos` — cada canal
/// tem preço/disponibilidade próprios e cache separado.
class MenuStore extends ChangeNotifier {
  MenuStore(this._api, this._store);

  final Api _api;
  final LocalStore _store;

  List<MenuCategory> categories = const [];
  bool loading = false;
  String? error;
  String channel = 'table';
  DateTime? _fetchedAt;

  String _cacheName(String ch) => ch == 'table' ? 'menu' : 'menu_$ch';

  Future<void> fetch([String ch = 'table']) async {
    if (categories.isNotEmpty && channel == ch) {
      // Já carregado: revalida em segundo plano se estiver velho.
      if (_fetchedAt == null || DateTime.now().difference(_fetchedAt!) > const Duration(minutes: 3)) {
        revalidate();
      }
      return;
    }
    loading = true;
    error = null;
    channel = ch;
    categories = const [];
    notifyListeners();
    try {
      await _load(ch);
    } on ApiException catch (e) {
      final cached = await _store.readCache(_cacheName(ch));
      if (cached is Map) {
        categories = _parse(cached.cast<String, dynamic>());
      } else {
        error = e.isNetwork ? 'Cardápio indisponível sem conexão.' : 'Não foi possível carregar o cardápio.';
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final ch = channel;
    categories = const [];
    await fetch(ch);
  }

  bool _revalidating = false;

  /// Recarrega sem esvaziar a lista nem ligar o loading: a tela continua
  /// navegável e só troca quando a resposta chega.
  Future<void> revalidate() async {
    if (categories.isEmpty || loading || _revalidating) return;
    _revalidating = true;
    final ch = channel;
    try {
      await _load(ch);
      error = null;
      notifyListeners();
    } on ApiException {
      // mantém o cardápio atual
    } finally {
      _revalidating = false;
    }
  }

  Future<void> _load(String ch) async {
    final data = await _api.get('/menu', query: ch == 'table' ? null : {'channel': ch});
    if (channel != ch) return; // trocou de canal no meio do caminho
    categories = _parse(data);
    _fetchedAt = DateTime.now();
    _store.writeCache(_cacheName(ch), data);
  }

  List<MenuCategory> _parse(Json data) =>
      dedupeCategories(asList(data['categories']).map(MenuCategory.fromJson).toList());

  /// Produto do carrinho que deixou de poder ser vendido (indisponível ou
  /// fora do cardápio). Sem cardápio carregado não há como saber → false.
  bool isUnavailable(String productId) {
    if (categories.isEmpty) return false;
    for (final cat in categories) {
      for (final p in cat.products) {
        if (p.id == productId) return !p.isAvailable;
      }
    }
    return true;
  }

  void reset() {
    categories = const [];
    loading = false;
    error = null;
    _fetchedAt = null;
    notifyListeners();
  }
}
