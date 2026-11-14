import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/product_builder.dart';
import '../core/uuid.dart';
import '../models/models.dart';
import 'menu.dart';
import 'session.dart';
import 'tables.dart';

/// Carrinho de um pedido ainda não enviado (mesa) ou de uma venda (balcão).
///
/// Guarda a chave de idempotência ESTÁVEL do carrinho: reenviar depois de um
/// timeout usa a mesma chave e não duplica. A chave só troca quando o envio é
/// confirmado ([commit]) ou o carrinho é descartado ([discard]).
class OrderCart extends ChangeNotifier {
  final List<CartItem> _items = [];
  String _key = uuidV7();

  /// Motivo pelo qual os itens não podem mudar agora (balcão com pagamento
  /// já cobrado na maquininha). `null` = livre.
  String? lockReason;

  List<CartItem> get items => List.unmodifiable(_items);
  String get key => _key;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  bool get locked => lockReason != null;

  double get total => _items.fold(0, (a, i) => a + i.total);

  /// Unidades no carrinho (item por peso conta 1).
  int get count => _items.fold(0, (a, i) => a + _units(i));

  static int _units(CartItem i) => i.product.allowFractionalQty ? 1 : i.quantity.round();

  /// Quantas unidades deste produto estão no carrinho, somando as linhas.
  int qtyOf(String productId) => _items.where((i) => i.product.id == productId).fold(0, (a, i) => a + _units(i));

  /// Linha "simples" do produto: sem observação, adicional, sabor ou combo.
  /// É a linha que o "+" do cardápio incrementa.
  CartItem? _plainLine(String productId) => _items.where((i) => i.product.id == productId && _isPlain(i)).firstOrNull;

  static bool _isPlain(CartItem i) =>
      !i.product.allowFractionalQty &&
      i.notes.isEmpty &&
      i.addons.isEmpty &&
      i.selectedFlavorIds.isEmpty &&
      i.comboSelections.isEmpty;

  /// O "+" do cardápio ainda pode lançar mais um deste produto?
  bool canAddOne(MenuProduct product) => !locked && (_plainLine(product.id)?.quantity ?? 0) < maxLineQuantity;

  /// "+" do cardápio em produto simples: lança 1 na hora. Devolve `false` se
  /// nada mudou (carrinho travado ou linha no teto).
  bool addOne(MenuProduct product) {
    if (!canAddOne(product)) return false;
    final line = _plainLine(product.id);
    if (line != null) {
      line.quantity += 1;
    } else {
      _items.add(CartItem(localId: uuidV7(), product: product, quantity: 1, unitPrice: product.price));
    }
    notifyListeners();
    return true;
  }

  /// "−" do cardápio: tira 1 da última linha do produto; em zero, remove.
  void removeOne(String productId) {
    if (locked) return;
    final index = _items.lastIndexWhere((i) => i.product.id == productId);
    if (index < 0) return;
    final line = _items[index];
    if (line.product.allowFractionalQty || line.quantity <= 1) {
      _items.removeAt(index);
    } else {
      line.quantity -= 1;
    }
    notifyListeners();
  }

  /// Item montado numa janela. Um item simples igual a uma linha que já
  /// existe (mesmo produto e mesma observação) soma na linha.
  void add(CartItem item) {
    if (locked) return;
    final same = _items
        .where((i) => i.product.id == item.product.id && _mergeable(i) && _mergeable(item) && i.notes == item.notes)
        .firstOrNull;
    if (same != null) {
      final next = same.quantity + item.quantity;
      same.quantity = next > maxLineQuantity ? maxLineQuantity.toDouble() : next;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  static bool _mergeable(CartItem i) =>
      !i.product.allowFractionalQty && i.addons.isEmpty && i.selectedFlavorIds.isEmpty && i.comboSelections.isEmpty;

  /// −/+ de uma linha na revisão: abaixo de 1 remove; teto de 99.
  void changeQty(CartItem item, int delta) {
    if (locked || !_items.contains(item)) return;
    final next = item.quantity + delta;
    if (next < 1) {
      _items.remove(item);
    } else {
      item.quantity = next > maxLineQuantity ? maxLineQuantity.toDouble() : next;
    }
    notifyListeners();
  }

  void remove(CartItem item) {
    if (locked) return;
    if (_items.remove(item)) notifyListeners();
  }

  /// Descarta o pedido em montagem: o próximo é outro carrinho (chave nova).
  void discard() => _reset();

  /// Envio confirmado pelo servidor: esvazia e troca a chave.
  void commit() => _reset();

  void _reset() {
    _items.clear();
    _key = uuidV7();
    lockReason = null;
    notifyListeners();
  }
}

/// Resultado de [TableOrderDraft.submit].
class OrderSubmitResult {
  const OrderSubmitResult({
    this.error,
    this.sessionId,
    this.kitchenSent = true,
    this.items = const [],
    this.count = 0,
    this.comandaLabel,
    this.customerName,
  });

  /// `null` = pedido gravado.
  final String? error;
  final String? sessionId;

  /// `false` = gravado, mas a produção não recebeu (não reenviar).
  final bool kitchenSent;

  /// Itens enviados (para a via impressa).
  final List<CartItem> items;

  /// Unidades enviadas ("4 itens da mesa 7").
  final int count;
  final String? comandaLabel;
  final String? customerName;

  bool get ok => error == null;
}

/// Pedido em montagem de UMA mesa: o carrinho e, para mesa livre, os dados de
/// abertura (pessoas, cliente e comandas) que antes ficavam no formulário
/// "Abrir mesa". É o que o Cardápio e a Revisão compartilham.
///
/// Mesa livre: nada vai ao servidor até [submit], que primeiro abre a mesa
/// (`TablesStore.open`) e depois envia o pedido (`SessionStore.sendCart`). Se
/// a abertura der certo e o envio falhar, a sessão criada fica guardada em
/// [sessionId] e a nova tentativa reenvia só o pedido, com a mesma chave.
class TableOrderDraft extends ChangeNotifier {
  /// Mesa livre, ainda sem atendimento no servidor.
  TableOrderDraft.freeTable(
    DiningTable this.table, {
    required this._tables,
    required this._session,
    required this._menu,
    this.allowComandas = false,
  }) : _title = table.title,
       sessionId = null {
    cart.addListener(notifyListeners);
  }

  /// Mesa que já tem atendimento aberto.
  TableOrderDraft.session({
    required String this.sessionId,
    required this._title,
    required this._tables,
    required this._session,
    required this._menu,
  }) : table = null,
       allowComandas = false {
    cart.addListener(notifyListeners);
  }

  final TablesStore _tables;
  final SessionStore _session;
  final MenuStore _menu;

  final cart = OrderCart();

  /// A mesa livre que originou o pedido (`null` quando já estava aberta).
  final DiningTable? table;

  final String _title;

  /// "Mesa 7", "Comanda 101": o nome que o servidor dá à mesa, quando a
  /// sessão já está carregada; senão, o informado por quem abriu o fluxo.
  String get title => _loaded?.title ?? _title;

  /// Atendimento no servidor. `null` enquanto a mesa livre não foi aberta.
  String? sessionId;

  /// A loja usa comandas e esta mesa pode ter (só importa na mesa livre).
  final bool allowComandas;

  // ── Dados de abertura (mesa livre) ────────────────────────────────────────

  /// Pessoas na mesa; `null` = não informado (como o campo vazio de antes).
  int? guestCount;
  String customerName = '';
  bool withComandas = false;
  final List<String> comandaLabels = [];

  /// Mesa nova com várias comandas: em qual lançar este pedido (rótulo).
  String? comandaLabel;

  /// Mesa já aberta com comandas: a comanda que recebe o pedido.
  String? comandaId;

  bool _busy = false;
  bool get busy => _busy;

  /// A mesa ainda não existe no servidor.
  bool get isNewTable => sessionId == null;

  /// A mesa foi aberta por este pedido (interessa ao descartar depois de uma
  /// falha de envio: a mesa continua aberta, vazia).
  bool get openedHere => table != null && sessionId != null;

  void setGuestCount(int? value) {
    guestCount = (value == null || value < 1) ? null : (value > 100 ? 100 : value);
    notifyListeners();
  }

  void setWithComandas(bool value) {
    withComandas = value;
    notifyListeners();
  }

  /// Acrescenta uma comanda inicial (sem repetir rótulo).
  void addComandaLabel(String raw) {
    final label = raw.trim();
    if (label.isEmpty) return;
    if (!comandaLabels.any((l) => l.toLowerCase() == label.toLowerCase())) comandaLabels.add(label);
    notifyListeners();
  }

  void removeComandaLabel(String label) {
    comandaLabels.remove(label);
    if (comandaLabel == label) comandaLabel = null;
    notifyListeners();
  }

  void chooseComandaLabel(String label) {
    comandaLabel = label;
    notifyListeners();
  }

  void chooseComanda(String id) {
    comandaId = id;
    notifyListeners();
  }

  /// Comandas que a mesa nova terá ao abrir.
  List<String> get openingComandas =>
      isNewTable && allowComandas && withComandas ? List.unmodifiable(comandaLabels) : const [];

  /// Rótulo da comanda que recebe o pedido da mesa nova: a única criada ou a
  /// escolhida. `null` = sem comanda, ou falta escolher.
  String? get _targetLabel {
    final labels = openingComandas;
    if (labels.isEmpty) return null;
    if (labels.length == 1) return labels.first;
    return labels.contains(comandaLabel) ? comandaLabel : null;
  }

  /// Sessão carregada no `SessionStore`, se for a deste pedido.
  SessionDetail? get _loaded => _session.session?.id == sessionId ? _session.session : null;

  /// Mesa aberta com comandas: a comanda que recebe o pedido. Vale a
  /// escolhida; havendo uma só aberta, é ela. `null` = sem comanda (mesa sem
  /// comandas ou sessão não carregada) ou falta escolher.
  String? get targetComandaId {
    final s = _loaded;
    if (s == null || !s.hasComandas) return null;
    final open = s.openComandas;
    if (open.any((c) => c.id == comandaId)) return comandaId;
    return open.length == 1 ? open.first.id : null;
  }

  /// Por que o pedido não pode ser enviado agora (`null` = pode tentar).
  String? get blockReason {
    if (cart.isEmpty) return 'Adicione itens ao pedido.';
    if (cart.items.any((i) => _menu.isUnavailable(i.product.id))) {
      return 'Há item indisponível no pedido. Remova antes de enviar.';
    }
    if (isNewTable) {
      return openingComandas.length > 1 && _targetLabel == null ? 'Selecione a comanda para enviar o pedido.' : null;
    }
    // Mesa recém-aberta com comanda ainda por resolver: resolve no envio.
    if (_pendingLabel != null) return null;
    final s = _loaded;
    if (s == null) return table == null ? 'Mesa não carregada.' : null;
    if (s.hasComandas && targetComandaId == null) return 'Selecione a comanda para enviar o pedido.';
    return null;
  }

  /// Rótulo ainda por resolver em id (a mesa abriu, mas a leitura da sessão
  /// ou o envio falharam).
  String? _pendingLabel;

  /// Envia o pedido. Mesa livre: abre a mesa antes (uma única vez).
  Future<OrderSubmitResult> submit() async {
    if (_busy) return const OrderSubmitResult(error: 'Envio em andamento.');
    final block = blockReason;
    if (block != null) return OrderSubmitResult(error: block);
    _busy = true;
    notifyListeners();
    try {
      return await _submit();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<OrderSubmitResult> _submit() async {
    // 1) Mesa livre: grava pessoas, cliente e comandas no mesmo lugar em que o
    //    formulário "Abrir mesa" gravava. Só na primeira tentativa.
    if (sessionId == null) {
      final name = customerName.trim();
      _pendingLabel = _targetLabel;
      try {
        sessionId = await _tables.open(
          table!,
          guestCount: guestCount,
          customerName: name.isEmpty ? null : name,
          comandas: openingComandas,
        );
      } on ApiException catch (e) {
        _pendingLabel = null;
        return OrderSubmitResult(error: e.isNetwork ? e.message : 'Não foi possível abrir a mesa. ${e.message}');
      }
      _tables.fetch();
    }
    final id = sessionId!;

    // 2) Mesa nova com comandas: o pedido precisa do id da comanda, que só
    //    existe depois de abrir. Resolve o rótulo lendo a sessão.
    if (_pendingLabel != null) {
      await _session.fetch(id, silent: true);
      final s = _loaded;
      if (s == null) {
        return OrderSubmitResult(
          sessionId: id,
          error: 'A mesa foi aberta, mas não foi possível carregar as comandas. Toque em Enviar de novo.',
        );
      }
      final label = _pendingLabel!.trim().toLowerCase();
      comandaId = s.openComandas.where((c) => c.label.trim().toLowerCase() == label).firstOrNull?.id;
      _pendingLabel = null;
      if (s.hasComandas && targetComandaId == null) {
        return OrderSubmitResult(sessionId: id, error: 'Selecione a comanda para enviar o pedido.');
      }
    }

    // 3) O envio de sempre, com a chave estável do carrinho.
    final useComanda = targetComandaId;
    final sent = cart.items;
    final count = cart.count;
    final result = await _session.sendCart(id, sent, comandaId: useComanda, idempotencyKey: cart.key);
    if (!result.ok) return OrderSubmitResult(sessionId: id, error: result.error);

    final after = _loaded;
    final label = useComanda == null ? null : after?.comandas.where((c) => c.id == useComanda).firstOrNull?.label;
    cart.commit();
    _tables.fetch();
    return OrderSubmitResult(
      sessionId: id,
      kitchenSent: result.kitchenSent,
      items: sent,
      count: count,
      comandaLabel: label,
      customerName: after?.customerName ?? (customerName.trim().isEmpty ? null : customerName.trim()),
    );
  }

  /// Descarta o pedido em montagem (Cancelar no cardápio).
  void discard() => cart.discard();

  @override
  void dispose() {
    cart.removeListener(notifyListeners);
    cart.dispose();
    super.dispose();
  }
}
