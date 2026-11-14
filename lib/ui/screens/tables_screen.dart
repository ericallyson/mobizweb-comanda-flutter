import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../stores/tables.dart';
import '../kit.dart';
import '../sheets/open_table_sheet.dart';
import '../sheets/store_switch_sheet.dart';
import '../table_card.dart';
import '../table_status.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

/// Mapa de mesas (seção 5.1 do layout novo): topo navy com a loja, o garçom,
/// o sino e a busca com "Entrar"; chips de filtro com contagem; grade de 4
/// colunas. É uma ABA da [HomeShell]: não tem `Scaffold` próprio e quem
/// atualiza os dados de tempos em tempos é a casca.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final _search = TextEditingController();
  TableFilter _filter = TableFilter.all;
  bool _showComandas = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    app.tables.addListener(_changed);
    app.settings.addListener(_changed);
    app.ledger.addListener(_changed);
    app.notifications.addListener(_changed);
    app.auth.addListener(_changed);
    app.api.online.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.tables.removeListener(_changed);
    app.settings.removeListener(_changed);
    app.ledger.removeListener(_changed);
    app.notifications.removeListener(_changed);
    app.auth.removeListener(_changed);
    app.api.online.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  // ── Dados derivados ───────────────────────────────────────────────────────

  bool get _hasComandaTables => app.tables.tables.any((t) => t.isComanda);

  /// Mesas da aba aberta (Mesas ou Comandas), antes de filtro e busca.
  List<DiningTable> get _kindTables =>
      _hasComandaTables ? app.tables.tables.where((t) => t.isComanda == _showComandas).toList() : app.tables.tables;

  static const _statusOrder = {'occupied': 0, 'closing': 1, 'reserved': 2, 'available': 3};

  List<DiningTable> _filtered(DateTime now) {
    final limit = app.tables.idleAlertMinutes;
    final sorted = _kindTables
        .where((t) => tableMatchesFilter(t, _filter, limit, now) && tableMatchesQuery(t, _search.text))
        .toList();
    int byNumber(DiningTable a, DiningTable b) => naturalCompare(tableNumberKey(a), tableNumberKey(b));
    switch (app.settings.sortMode) {
      case 'title':
        sorted.sort((a, b) => naturalCompare(a.title, b.title));
      case 'status':
        sorted.sort((a, b) {
          final c = (_statusOrder[a.status] ?? 9).compareTo(_statusOrder[b.status] ?? 9);
          return c != 0 ? c : byNumber(a, b);
        });
      default:
        sorted.sort(byNumber);
    }
    return sorted;
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _push(Widget screen) async {
    FocusScope.of(context).unfocus();
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) app.tables.fetch();
  }

  /// Toque num card (ou "Entrar"): mesa livre começa um atendimento; mesa com
  /// atendimento abre a tela da mesa.
  Future<void> _onTable(DiningTable table) async {
    if (_opening) return;
    if (table.status == 'available') {
      await _startFreeTable(table);
    } else if (table.session != null) {
      await _openSession(table.session!.id, table.title);
    }
  }

  Future<void> _openSession(String sessionId, String title) async {
    app.session.clear();
    await _push(SessionScreen(sessionId: sessionId, title: title));
  }

  /// TOQUE EM MESA LIVRE: vai direto ao Cardápio (seção 5.2 do plano). Nada
  /// é criado no servidor aqui: a mesa só é aberta quando o garçom toca
  /// "Enviar para cozinha" em "Revisar pedido", que é onde ficam os campos do
  /// antigo formulário "Abrir mesa" (pessoas, cliente e comandas).
  Future<void> _startFreeTable(DiningTable table) async {
    final p = app.auth.permissions;
    if (!p.openSession) {
      toast(context, 'Seu usuário não tem permissão para abrir mesas.', error: true);
      return;
    }
    // Quem pode abrir mesa mas não pode lançar pedido continua abrindo a mesa
    // vazia pelo formulário (o cardápio não serviria para nada).
    if (!p.createOrder) return _openWithoutOrder(table);

    FocusScope.of(context).unfocus();
    app.session.clear();
    final draft = freeTableDraft(table);
    final result = await openTableMenu(context, draft);
    draft.dispose();
    if (!mounted) return;
    app.tables.fetch();
    if (result.exit == OrderFlowExit.stay && result.sessionId != null) {
      await _openSession(result.sessionId!, table.title);
    }
  }

  /// Abre a mesa sem pedido, pelo formulário "Abrir mesa" (só para quem não
  /// tem permissão de lançar pedidos).
  Future<void> _openWithoutOrder(DiningTable table) async {
    final data = await showSheet<OpenTableData>(
      context,
      (_) => OpenTableSheet(
        table: table,
        enableComandas: app.tables.enableComandas && !(table.label?.startsWith('Comanda') ?? false) && !table.isComanda,
      ),
    );
    if (data == null || !mounted) return;
    setState(() => _opening = true);
    try {
      final sessionId = await app.tables.open(
        table,
        guestCount: data.guestCount,
        customerName: data.customerName,
        comandas: data.comandas,
      );
      if (!mounted) return;
      app.tables.fetch();
      await _openSession(sessionId, table.title);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.isNetwork ? e.message : 'Não foi possível abrir a mesa. ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Botão "Entrar": abre direto a mesa ou comanda digitada.
  Future<void> _enter() async {
    final typed = _search.text.trim();
    if (typed.isEmpty) return;
    FocusScope.of(context).unfocus();
    final table = findTableForEntry(app.tables.tables, typed, preferComanda: _showComandas);
    if (table == null) {
      final n = typed.replaceFirst(RegExp(r'^(mesa|comanda)\s*', caseSensitive: false), '');
      toast(context, 'Mesa $n não existe neste salão');
      return;
    }
    if (table.status != 'available' && table.session == null) {
      toast(
        context,
        '${table.title} está ${tableStatusStyle(table.status).label.toLowerCase()} e não tem atendimento aberto',
      );
      return;
    }
    _search.clear();
    setState(() {});
    await _onTable(table);
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = app.auth;
    final store = app.tables;
    final now = DateTime.now();
    final filtered = _filtered(now);
    final counts = countTablesByFilter(_kindTables, store.idleAlertMinutes, now);
    final offline = !app.api.online.value;
    final pendingTef = app.ledger.pending.length;
    final waiter = auth.user?.name.trim() ?? '';

    // Um filtro que deixou de existir (ex.: a última reserva saiu) volta a "Todas".
    if ((_filter == TableFilter.reserved || _filter == TableFilter.pending) && (counts[_filter] ?? 0) == 0) {
      _filter = TableFilter.all;
    }

    return ColoredBox(
      color: C.bg,
      child: Column(
        children: [
          AppHeader(
            title: auth.store?.name ?? 'Mesas',
            titleWidget: _storeTitle(),
            subtitle: waiter.isEmpty ? null : 'Garçom $waiter',
            actions: [
              HeaderButton(
                icon: Icons.notifications_none,
                tooltip: 'Notificações',
                badge: app.notifications.count,
                onTap: () => openNotifications(context),
              ),
            ],
            bottom: _quickEntry(),
          ),
          if (offline)
            Note(
              store.lastFetchedAt == null
                  ? 'Sem conexão com o servidor.'
                  : 'Sem conexão com o servidor. Mostrando os dados das ${hhmmss(store.lastFetchedAt!)}.',
              radius: 0,
            ),
          if (pendingTef > 0)
            Note(
              pendingTef == 1
                  ? '1 pagamento da maquininha sem registro. Toque para resolver.'
                  : '$pendingTef pagamentos da maquininha sem registro. Toque para resolver.',
              kind: NoteKind.error,
              radius: 0,
              onTap: () => _push(const SettingsScreen(openPending: true)),
            ),
          if (_hasComandaTables) _kindTabs(),
          _filterChips(counts),
          Expanded(child: _body(filtered, now)),
        ],
      ),
    );
  }

  /// Nome da loja com "▾": toque abre a troca de loja (quando há mais de uma).
  Widget? _storeTitle() {
    final auth = app.auth;
    if (auth.store == null) return null;
    final name = Text(auth.store!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.top);
    if (!auth.hasMultipleStores) return name;
    return Semantics(
      button: true,
      label: 'Trocar loja. Loja atual: ${auth.store!.name}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showStoreSwitch(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: name),
            const Icon(Icons.arrow_drop_down, size: 22, color: C.white),
          ],
        ),
      ),
    );
  }

  /// Campo "Buscar mesa ou comanda" + botão "Entrar". Filtra enquanto digita.
  Widget _quickEntry() => SizedBox(
    height: 44,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _enter(),
              textInputAction: TextInputAction.go,
              autocorrect: false,
              textAlignVertical: TextAlignVertical.center,
              style: T.body(w: T.medium),
              decoration: InputDecoration(
                hintText: 'Buscar mesa ou comanda',
                hintStyle: T.body(w: T.medium, c: C.sub),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : Semantics(
                        button: true,
                        label: 'Limpar busca',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(_search.clear),
                          child: const Icon(Icons.close, size: 18, color: C.sub),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tap(
          onTap: _enter,
          color: C.magenta,
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text(
              'Entrar',
              style: T.s(14, w: T.bold, c: C.white, h: 1.2),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _body(List<DiningTable> filtered, DateTime now) {
    final store = app.tables;
    if (store.loading && store.tables.isEmpty) return const StateView(text: 'Carregando mesas...');
    if (store.error != null && store.tables.isEmpty) {
      return StateView(text: store.error!, error: true, onAction: store.fetch);
    }
    if (filtered.isEmpty) {
      return RefreshIndicator(
        color: C.navy,
        onRefresh: store.fetch,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: box.maxHeight,
              child: const StateView(text: 'Nenhuma mesa encontrada.'),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: C.navy,
      onRefresh: store.fetch,
      child: TableGrid(tables: filtered, idleLimitMinutes: store.idleAlertMinutes, now: now, onTap: _onTable),
    );
  }

  /// Abas Mesas | Comandas (só quando a loja tem comanda física).
  Widget _kindTabs() {
    final mesas = app.tables.tables.where((t) => !t.isComanda).length;
    final comandas = app.tables.tables.length - mesas;
    Widget tab(String label, int count, bool comandaTab) {
      final active = _showComandas == comandaTab;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _showComandas = comandaTab;
              _filter = TableFilter.all;
            }),
            // 4 px de respiro dentro da área de toque: 44 px de toque, 36 de aba.
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? C.navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('$label $count', style: T.num(12.5, c: active ? C.white : C.sub, h: 1.2)),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [tab('Mesas', mesas, false), tab('Comandas', comandas, true)]),
      ),
    );
  }

  /// Faixa de chips: bolinha da cor do status, nome e contagem. "Reservas" e
  /// "Pendentes" só aparecem quando existem.
  Widget _filterChips(Map<TableFilter, int> counts) {
    final chips = <(TableFilter, String, Color?)>[
      (TableFilter.all, 'Todas', null),
      (TableFilter.available, 'Livres', tableGroupStyle(TableFilter.available).bg),
      (TableFilter.occupied, 'Ocupadas', tableGroupStyle(TableFilter.occupied).bg),
      (TableFilter.closing, 'Fechando', tableGroupStyle(TableFilter.closing).bg),
      (TableFilter.idle, 'Ociosas', tableGroupStyle(TableFilter.idle).bg),
      if ((counts[TableFilter.reserved] ?? 0) > 0)
        (TableFilter.reserved, 'Reservas', tableGroupStyle(TableFilter.reserved).bg),
      if ((counts[TableFilter.pending] ?? 0) > 0) (TableFilter.pending, 'Pendentes', C.magenta),
    ];
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Row(
          children: [
            for (final (i, (value, label, dot)) in chips.indexed)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                child: FilterPill(
                  label: label,
                  count: counts[value] ?? 0,
                  dot: dot,
                  selected: _filter == value,
                  onTap: () => setState(() => _filter = value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
