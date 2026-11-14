import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/addon_rules.dart';
import '../../core/product_builder.dart';
import '../../models/models.dart';
import '../../stores/order_draft.dart';
import '../kit.dart';
import '../order_widgets.dart';
import '../sheets/product_sheet.dart';
import 'review_screen.dart';

// ── Fluxo da mesa: Cardápio → Revisar pedido ─────────────────────────────────

/// Como o fluxo Cardápio → Revisão de uma mesa terminou.
enum OrderFlowExit {
  /// Cancelou ou voltou: nada foi enviado e o carrinho foi descartado.
  canceled,

  /// Tocou em "Conta": quer ver a mesa aberta. O carrinho continua no
  /// [TableOrderDraft] (nada foi descartado).
  bill,

  /// Enviou o pedido e escolheu "Voltar às mesas".
  tables,

  /// Enviou o pedido e escolheu "Ficar na mesa".
  stay,
}

/// O que [openTableMenu] devolve ao fechar.
class OrderFlowResult {
  const OrderFlowResult(this.exit, {this.sessionId, this.notice});
  final OrderFlowExit exit;

  /// Atendimento da mesa no servidor. Numa mesa livre só existe depois que o
  /// pedido abriu a mesa (pode existir mesmo em [OrderFlowExit.canceled], se
  /// a mesa abriu e o envio falhou).
  final String? sessionId;

  /// Aviso que a tela da mesa deve manter visível (pedido gravado que não
  /// saiu na produção).
  final String? notice;

  bool get sent => exit == OrderFlowExit.tables || exit == OrderFlowExit.stay;
}

/// Pedido novo de uma mesa LIVRE: nada vai ao servidor até "Enviar para
/// cozinha".
TableOrderDraft freeTableDraft(DiningTable table) => TableOrderDraft.freeTable(
  table,
  tables: app.tables,
  session: app.session,
  menu: app.menu,
  // Mesma regra do formulário "Abrir mesa": comanda física não tem comandas.
  allowComandas: app.tables.enableComandas && !(table.label?.startsWith('Comanda') ?? false) && !table.isComanda,
);

/// Pedido de uma mesa que já tem atendimento aberto.
TableOrderDraft sessionDraft({required String sessionId, required String title}) => TableOrderDraft.session(
  sessionId: sessionId,
  title: title,
  tables: app.tables,
  session: app.session,
  menu: app.menu,
);

/// Abre o Cardápio da mesa (e, dele, "Revisar pedido"). O [draft] é de quem
/// chama: depois de [OrderFlowExit.bill] ele ainda guarda o carrinho.
Future<OrderFlowResult> openTableMenu(BuildContext context, TableOrderDraft draft) async =>
    await Navigator.push<OrderFlowResult>(context, MaterialPageRoute(builder: (_) => TableMenuScreen(draft: draft))) ??
    OrderFlowResult(OrderFlowExit.canceled, sessionId: draft.sessionId);

/// Cardápio de uma mesa (5.2 do plano). Fecha devolvendo [OrderFlowResult].
class TableMenuScreen extends StatefulWidget {
  const TableMenuScreen({super.key, required this.draft});
  final TableOrderDraft draft;

  @override
  State<TableMenuScreen> createState() => _TableMenuScreenState();
}

class _TableMenuScreenState extends State<TableMenuScreen> with StoreRebuild {
  TableOrderDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    draft.addListener(rebuild);
    app.session.addListener(rebuild);
    final id = draft.sessionId;
    if (id != null && app.session.session?.id != id) app.session.fetch(id);
  }

  @override
  void dispose() {
    draft.removeListener(rebuild);
    app.session.removeListener(rebuild);
    super.dispose();
  }

  SessionDetail? get _s => app.session.session?.id == draft.sessionId ? app.session.session : null;

  String get _subtitle {
    final waiter = app.auth.user?.name.trim() ?? '';
    if (draft.isNewTable) return ['Nova mesa', if (waiter.isNotEmpty) waiter].join(' · ');
    final s = _s;
    final customer = s?.customerName ?? draft.table?.session?.customerName ?? draft.customerName.trim();
    final guests = s?.guestCount ?? draft.guestCount;
    final parts = [
      if (customer.isNotEmpty) customer,
      if (guests != null && guests > 0) guests == 1 ? '1 pessoa' : '$guests pessoas',
    ];
    return parts.isEmpty ? waiter : parts.join(' · ');
  }

  Future<void> _cancel() async {
    if (draft.busy) return;
    if (draft.cart.isNotEmpty) {
      final n = draft.cart.count;
      final ok = await confirm(
        context,
        title: 'Descartar o pedido?',
        message:
            '${n == 1 ? 'O item do carrinho ainda não foi enviado' : 'Os $n itens do carrinho ainda não foram enviados'} '
            'para a cozinha.${draft.openedHere ? ' A mesa já foi aberta e continua aberta, sem itens.' : ''}',
        confirmLabel: 'Descartar',
        cancelLabel: 'Continuar',
        danger: true,
      );
      if (!ok || !mounted) return;
      draft.discard();
    }
    Navigator.pop(context, OrderFlowResult(OrderFlowExit.canceled, sessionId: draft.sessionId));
  }

  Future<void> _review() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<OrderFlowResult>(
      context,
      MaterialPageRoute(builder: (_) => ReviewScreen(draft: draft)),
    );
    // `null` = "+ Itens" ou voltar: continua no cardápio.
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final hasSent = s != null && s.activeItems.isNotEmpty;
    return MenuScreen(
      cart: draft.cart,
      title: draft.title,
      subtitle: _subtitle,
      blockedText: app.auth.permissions.createOrder ? null : 'Seu usuário não tem permissão para lançar pedidos.',
      actions: [
        if (hasSent)
          HeaderButton.text(
            'Conta',
            onTap: () => Navigator.pop(context, OrderFlowResult(OrderFlowExit.bill, sessionId: draft.sessionId)),
          ),
      ],
      primaryLabel: 'Revisar pedido',
      onPrimary: _review,
      onCancel: _cancel,
    );
  }
}

// ── A tela do cardápio (mesa e balcão) ───────────────────────────────────────

/// Cardápio (5.2 do plano): busca no topo, categorias em blocos de duas
/// linhas e produtos em cartões com "+" direto na linha. É a mesma tela para
/// mesa ([TableMenuScreen]) e balcão (`CounterScreen`); quem usa decide o que
/// "Cancelar" e o botão principal fazem.
class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    required this.cart,
    required this.title,
    this.subtitle,
    this.channel = 'table',
    this.actions = const [],
    this.banner,
    this.blockedText,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCancel,
  });

  final OrderCart cart;
  final String title;
  final String? subtitle;

  /// Canal do cardápio: `table` (mesa) ou `pos` (balcão).
  final String channel;

  /// Botões à direita do título ("Conta").
  final List<Widget> actions;

  /// Faixa de aviso abaixo do topo (ex.: erro do recebimento no balcão).
  final Widget? banner;

  /// Quando preenchido, a tela mostra só este texto (sem permissão).
  final String? blockedText;

  /// Nome do botão principal: "Revisar pedido", "Ver venda".
  final String primaryLabel;
  final VoidCallback onPrimary;

  /// "Cancelar", voltar do topo e voltar do aparelho.
  final VoidCallback onCancel;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with StoreRebuild {
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  static const _noCategory = '__sem_categoria__';

  /// Categoria raiz selecionada (`null` até o cardápio chegar).
  String? _rootId;

  OrderCart get cart => widget.cart;

  @override
  void initState() {
    super.initState();
    app.menu.addListener(rebuild);
    app.api.online.addListener(rebuild);
    cart.addListener(rebuild);
    app.menu.fetch(widget.channel);
  }

  @override
  void didUpdateWidget(MenuScreen old) {
    super.didUpdateWidget(old);
    if (old.cart != cart) {
      old.cart.removeListener(rebuild);
      cart.addListener(rebuild);
    }
  }

  @override
  void dispose() {
    app.menu.removeListener(rebuild);
    app.api.online.removeListener(rebuild);
    cart.removeListener(rebuild);
    _search.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  // ── Dados ─────────────────────────────────────────────────────────────────

  static String _idOf(MenuCategory c) => c.id ?? _noCategory;

  List<MenuCategory> get _roots => app.menu.categories.where((c) => c.parentId == null).toList();

  List<MenuCategory> _childrenOf(MenuCategory c) =>
      c.id == null ? const [] : app.menu.categories.where((x) => x.parentId == c.id).toList();

  /// Produtos da raiz e, em seções, os das subcategorias (em qualquer nível).
  List<({String? label, List<MenuProduct> products})> _sectionsOf(MenuCategory root) {
    final out = <({String? label, List<MenuProduct> products})>[];
    void visit(MenuCategory c, String? label, int depth) {
      final own = c.products.where((p) => p.isAvailable).toList();
      if (own.isNotEmpty) out.add((label: label, products: own));
      if (depth > 6) return;
      for (final child in _childrenOf(c)) {
        visit(child, label == null ? child.name : '$label › ${child.name}', depth + 1);
      }
    }

    visit(root, null, 0);
    return out;
  }

  /// A raiz de cada produto, para a cor do quadrado de iniciais.
  Map<String, int> _colorIndexByProduct(List<MenuCategory> roots) {
    final out = <String, int>{};
    for (final (i, root) in roots.indexed) {
      for (final section in _sectionsOf(root)) {
        for (final p in section.products) {
          out.putIfAbsent(p.id, () => i);
        }
      }
    }
    return out;
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  bool _refuseIfLocked() {
    final reason = cart.lockReason;
    if (reason == null) return false;
    toast(context, reason, error: true);
    return true;
  }

  /// "+" na linha: produto simples entra na hora; os demais abrem a janela.
  Future<void> _plus(MenuProduct p) async {
    if (_refuseIfLocked()) return;
    if (needsBuilder(p) || p.allowFractionalQty) return _open(p);
    cart.addOne(p);
  }

  /// Toque no nome (ou "+" de produto que exige escolha): janela do produto.
  Future<void> _open(MenuProduct p) async {
    if (_refuseIfLocked()) return;
    FocusScope.of(context).unfocus();
    final item = await showProductSheet(context, p);
    if (item != null) cart.add(item);
  }

  void _selectRoot(MenuCategory c) {
    FocusScope.of(context).unfocus();
    setState(() {
      _rootId = _idOf(c);
      _search.clear();
    });
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final menu = app.menu;
    final roots = _roots;
    final q = fold(_search.text.trim());
    final searching = q.isNotEmpty;
    // A primeira categoria já vem selecionada; se a selecionada sumiu do
    // cardápio, volta para a primeira.
    final root = roots.where((c) => _idOf(c) == _rootId).firstOrNull ?? roots.firstOrNull;

    final Widget body;
    if (widget.blockedText != null) {
      body = StateView(icon: Icons.lock_outline, text: widget.blockedText!);
    } else if (menu.loading && menu.categories.isEmpty) {
      body = const StateView(text: 'Carregando cardápio...');
    } else if (menu.error != null && menu.categories.isEmpty) {
      body = StateView(text: menu.error!, error: true, onAction: menu.refresh);
    } else if (roots.isEmpty) {
      body = const StateView(text: 'Nenhuma categoria disponível.');
    } else {
      body = Column(
        children: [
          _categories(roots, searching ? null : root),
          Expanded(child: _products(roots, root, q)),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onCancel();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(
          children: [
            AppHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              onBack: widget.onCancel,
              actions: widget.actions,
              bottom: widget.blockedText == null ? _searchField() : null,
            ),
            if (!app.api.online.value) const Note('Sem conexão com o servidor.', radius: 0),
            ?widget.banner,
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: BottomBar.duo(
          Btn('Cancelar', kind: BtnKind.secondary, onTap: widget.onCancel),
          CountBtn(
            count: cart.count,
            label: widget.primaryLabel,
            total: cart.total,
            onTap: cart.isEmpty ? null : widget.onPrimary,
          ),
        ),
      ),
    );
  }

  /// "Buscar no cardápio", dentro do topo navy.
  Widget _searchField() => Container(
    height: 44,
    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.only(left: 12),
    child: Row(
      children: [
        const Icon(Icons.search, size: 18, color: Color(0xFFC9CBF0)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            autocorrect: false,
            cursorColor: C.white,
            style: T.body(w: T.medium, c: C.white),
            decoration: InputDecoration(
              hintText: 'Buscar no cardápio',
              hintStyle: T.body(w: T.medium, c: C.navySub),
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_search.text.isNotEmpty)
          Semantics(
            button: true,
            label: 'Limpar busca',
            child: InkResponse(
              onTap: () => setState(_search.clear),
              radius: 22,
              child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close, size: 18, color: C.navySub)),
            ),
          )
        else
          const SizedBox(width: 12),
      ],
    ),
  );

  /// Blocos de categoria: duas linhas, 4 por linha à vista, rolagem lateral
  /// quando passam de 8. A ordem é a do cadastro, lida de cima para baixo e
  /// da esquerda para a direita (coluna a coluna), como no protótipo.
  Widget _categories(List<MenuCategory> roots, MenuCategory? selected) {
    const gap = 6.0;
    const side = 14.0;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = (box.maxWidth - 2 * side - 3 * gap) / 4;
          Widget block(MenuCategory c) => _CategoryBlock(
            name: c.name,
            width: cell,
            selected: selected != null && _idOf(c) == _idOf(selected),
            onTap: () => _selectRoot(c),
          );
          // Até 4 categorias cabem numa linha só.
          final rows = roots.length <= 4 ? 1 : 2;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: side, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < roots.length; i += rows) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      block(roots[i]),
                      if (rows == 2 && i + 1 < roots.length) ...[const SizedBox(height: gap), block(roots[i + 1])],
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _products(List<MenuCategory> roots, MenuCategory? root, String q) {
    final colors = _colorIndexByProduct(roots);
    final rows = <Widget>[];
    if (q.isNotEmpty) {
      final seen = <String>{};
      final found = app.menu.categories
          .expand((c) => c.products)
          .where((p) => p.isAvailable && fold(p.name).contains(q) && seen.add(p.id))
          .toList();
      rows.addAll(found.map((p) => _card(p, colors)));
      if (found.isEmpty) rows.add(_empty('Nada encontrado para "${_search.text.trim()}".'));
    } else if (root != null) {
      for (final section in _sectionsOf(root)) {
        if (section.label != null) {
          rows.add(SectionLabel(section.label!, padding: EdgeInsets.fromLTRB(2, rows.isEmpty ? 0 : 6, 2, 0)));
        }
        rows.addAll(section.products.map((p) => _card(p, colors)));
      }
      if (rows.isEmpty) rows.add(_empty('Nenhum item nesta categoria.'));
    }
    return ListView.separated(
      controller: _listScroll,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: T.body(c: C.sub),
    ),
  );

  Widget _card(MenuProduct p, Map<String, int> colors) => _ProductCard(
    key: ValueKey(p.id),
    product: p,
    color: thumbPalette[(colors[p.id] ?? 0) % thumbPalette.length],
    quantity: cart.qtyOf(p.id),
    canAdd: cart.canAddOne(p) || cart.locked,
    onPlus: () => _plus(p),
    onMinus: () {
      if (!_refuseIfLocked()) cart.removeOne(p.id);
    },
    onOpen: () => _open(p),
  );
}

/// Bloco de categoria: navy, texto branco em maiúsculas; selecionado, magenta.
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.name, required this.width, required this.selected, required this.onTap});
  final String name;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = name.toUpperCase();
    final style = T.s(10.5, w: T.bold, c: C.white, h: 1.15).copyWith(letterSpacing: 0.2);
    final text = Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        width: width,
        height: 44,
        child: Tap(
          onTap: onTap,
          color: selected ? C.magenta : C.navy,
          radius: 10,
          splash: Colors.white24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          // Uma palavra só não quebra: encolhe para caber no bloco.
          child: Center(
            child: label.contains(' ') ? text : FittedBox(fit: BoxFit.scaleDown, child: text),
          ),
        ),
      ),
    );
  }
}

/// Cartão do produto: foto ou iniciais, nome, linha de apoio, preço e o "+"
/// (que vira contador −/+ depois do primeiro toque em produto simples).
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.product,
    required this.color,
    required this.quantity,
    required this.canAdd,
    required this.onPlus,
    required this.onMinus,
    required this.onOpen,
  });
  final MenuProduct product;
  final Color color;

  /// Unidades deste produto no carrinho.
  final int quantity;
  final bool canAdd;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onOpen;

  /// Linha de apoio. O cardápio não manda descrição: mostra só o que ele tem.
  String? get _hint {
    final p = product;
    if (p.pizza != null) {
      final n = p.pizza!.maxFlavors;
      return n > 1 ? 'Pizza · até $n sabores' : 'Pizza';
    }
    if (p.type == 'combo') return 'Combo';
    if (p.allowFractionalQty) return 'Vendido por ${p.unitOfMeasure ?? 'kg'}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final price = listPrice(p);
    final hint = _hint;
    // "+" direto: produto simples, sem escolha obrigatória e sem peso.
    final direct = !needsBuilder(p) && !p.allowFractionalQty;
    return Container(
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: quantity > 0 ? C.magenta : Colors.transparent, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(9, 6, 3, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Row(
                    children: [
                      ProductThumb(url: p.imageUrl, name: p.name, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.s(14, w: T.semibold, c: C.ink, h: 1.3),
                            ),
                            if (hint != null)
                              Text(
                                hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.s(12, c: C.sub, h: 1.3),
                              ),
                            if (p.onPromotion && !price.from)
                              // Promoção vigente: "de" riscado, "por" e o nome.
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${brl(p.originalPrice!)} ',
                                      style: T.s(
                                        12,
                                        c: C.sub,
                                        h: 1.35,
                                      ).copyWith(decoration: TextDecoration.lineThrough),
                                    ),
                                    TextSpan(text: brl(price.value)),
                                    if (p.promotion != null)
                                      TextSpan(
                                        text: '  ${p.promotion}',
                                        style: T.s(11.5, w: T.semibold, c: C.greenText, h: 1.35),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.num(13, c: C.greenText, h: 1.35),
                              )
                            else
                              Text(
                                price.from ? 'a partir de ${brl(price.value)}' : brl(price.value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.num(13, h: 1.35),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (direct && quantity > 0)
            QtyStepper(value: '$quantity', onMinus: onMinus, onPlus: canAdd ? onPlus : null)
          else ...[
            if (quantity > 0)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 16),
                child: Text('$quantity', textAlign: TextAlign.center, style: T.num(14)),
              ),
            _AddButton(label: 'Adicionar ${p.name}', onTap: onPlus),
          ],
        ],
      ),
    );
  }
}

/// O "+" magenta de 32 px (toque de 44), no mesmo lugar do "+" do contador.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: C.magenta),
          child: const Icon(Icons.add, size: 18, color: C.white),
        ),
      ),
    ),
  );
}
