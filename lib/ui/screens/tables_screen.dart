import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../stores/tables.dart';
import '../kit.dart';
import '../sheets/open_table_sheet.dart';
import '../table_status.dart';
import 'cash_screen.dart';
import 'counter_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

/// Mapa de mesas — a tela inicial, como `TablesListView.vue` do PWA.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> with WidgetsBindingObserver {
  final _search = TextEditingController();
  String _filter = 'all';
  bool _showComandas = false;
  bool _showSettings = false;
  bool _showStores = false;
  bool _switching = false;
  bool _opening = false;
  Timer? _poll;
  Timer? _tick;

  static const _filters = <(String, String)>[
    ('all', 'Todas'),
    ('available', 'Livres'),
    ('occupied', 'Ocupadas'),
    ('reserved', 'Reservas'),
    ('closing', 'Fechando'),
    ('pending', 'Pendentes'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.tables.addListener(_changed);
    app.settings.addListener(_changed);
    app.ledger.addListener(_changed);
    app.api.online.addListener(_onConnectivity);
    app.auth.refreshPermissions().then((_) => _changed());
    app.tables.fetch();
    app.methods.load();
    _startTimers();
  }

  void _startTimers() {
    _poll?.cancel();
    _tick?.cancel();
    // Sem WebSocket (a Stone proíbe no app embarcado): o mapa se atualiza por
    // polling, na mesma cadência do fallback do PWA.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ModalRoute.of(context)?.isCurrent ?? true) app.tables.fetch();
    });
    // Relógio do rótulo "Ociosa · N min".
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.tables.fetch();
      app.menu.revalidate();
      _startTimers();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _tick?.cancel();
    }
  }

  void _onConnectivity() {
    // Voltou a rede: registra o que a maquininha cobrou e ficou pendente.
    if (app.api.online.value) app.ledger.retryAll();
    _changed();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.tables.removeListener(_changed);
    app.settings.removeListener(_changed);
    app.ledger.removeListener(_changed);
    app.api.online.removeListener(_onConnectivity);
    _poll?.cancel();
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ── Dados derivados ───────────────────────────────────────────────────────

  bool get _hasComandaTables => app.tables.tables.any((t) => t.isComanda);

  List<DiningTable> get _kindTables => _hasComandaTables
      ? app.tables.tables.where((t) => t.isComanda == _showComandas).toList()
      : app.tables.tables;

  static const _statusOrder = {'occupied': 0, 'closing': 1, 'reserved': 2, 'available': 3};

  static String _numberKey(DiningTable t) => t.number.replaceFirst(RegExp(r'^mesa\s*', caseSensitive: false), '');

  List<DiningTable> get _filtered {
    var list = _kindTables;
    if (_filter == 'pending') {
      list = list.where((t) => t.pendingCalls > 0).toList();
    } else if (_filter != 'all') {
      list = list.where((t) => t.status == _filter).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) => t.title.toLowerCase().contains(q) || t.number.contains(q)).toList();
    }
    final sorted = [...list];
    int byNumber(DiningTable a, DiningTable b) => naturalCompare(_numberKey(a), _numberKey(b));
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
    setState(() {
      _showSettings = false;
      _showStores = false;
    });
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) app.tables.fetch();
  }

  Future<void> _onTable(DiningTable table) async {
    if (_opening) return;
    if (table.status == 'available') {
      if (!app.auth.permissions.openSession) {
        toast(context, 'Seu usuário não tem permissão para abrir mesas.', error: true);
        return;
      }
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
        app.session.clear();
        app.tables.fetch();
        await _push(SessionScreen(sessionId: sessionId, title: table.title));
      } on ApiException catch (e) {
        if (mounted) toast(context, e.isNetwork ? e.message : 'Não foi possível abrir a mesa. ${e.message}', error: true);
      } finally {
        if (mounted) setState(() => _opening = false);
      }
    } else if (table.session != null) {
      app.session.clear();
      await _push(SessionScreen(sessionId: table.session!.id, title: table.title));
    }
  }

  Future<void> _switchStore(StoreRef s) async {
    if (_switching) return;
    if (s.id == app.auth.store?.id) {
      setState(() => _showStores = false);
      return;
    }
    setState(() => _switching = true);
    final error = await app.auth.selectStore(s);
    if (!mounted) return;
    if (error == null) {
      app.resetDomain();
      app.tables.fetch();
      app.menu.fetch();
      app.methods.load(force: true);
    } else {
      toast(context, 'Não foi possível trocar de loja. Tente novamente.', error: true);
    }
    setState(() {
      _switching = false;
      _showStores = false;
    });
  }

  Future<void> _logout() async {
    final pending = app.ledger.pending.length;
    final ok = await confirm(
      context,
      title: 'Sair do app?',
      message: pending > 0
          ? 'Há $pending pagamento(s) da maquininha sem registro. Eles continuam guardados neste aparelho.'
          : 'Você volta para a tela de login.',
      confirmLabel: 'Sair',
      cancelLabel: 'Cancelar',
      danger: true,
    );
    if (ok) await app.auth.logout();
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = app.auth;
    final store = app.tables;
    final perms = auth.permissions;
    final canCash = perms.cashOpen || perms.cashClose || perms.cashMovement;
    final filtered = _filtered;
    final pendingTables = _kindTables.where((t) => t.pendingCalls > 0).length;
    final offline = !app.api.online.value;

    return Scaffold(
      backgroundColor: C.zinc50,
      body: Column(
        children: [
          AppHeader(
            title: 'Mesas',
            subtitleWidget: auth.store == null
                ? null
                : GestureDetector(
                    onTap: auth.hasMultipleStores ? () => setState(() => _showStores = !_showStores) : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            auth.store!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.xs(c: C.primary200),
                          ),
                        ),
                        if (auth.hasMultipleStores) const Icon(Icons.arrow_drop_down, size: 16, color: C.primary200),
                      ],
                    ),
                  ),
            actions: [
              if (perms.counterSale)
                HeaderButton(icon: Icons.shopping_cart_outlined, tooltip: 'Balcão', onTap: () => _push(const CounterScreen())),
              if (canCash)
                HeaderButton(icon: Icons.account_balance_wallet_outlined, tooltip: 'Caixa', onTap: () => _push(const CashScreen())),
              HeaderButton(
                icon: Icons.refresh,
                tooltip: 'Atualizar',
                spinning: store.loading,
                onTap: store.loading ? null : store.fetch,
              ),
              HeaderButton(
                icon: _showSettings ? Icons.close : Icons.settings_outlined,
                tooltip: 'Configurações',
                badge: app.ledger.pending.length,
                onTap: () => setState(() => _showSettings = !_showSettings),
              ),
            ],
          ),
          if (_showStores) _storeSwitcher(),
          if (offline)
            const Note('Sem conexão com o servidor — mostrando os últimos dados.', radius: 0),
          if (app.ledger.pending.isNotEmpty)
            Note(
              '${app.ledger.pending.length} pagamento(s) da maquininha sem registro — toque para resolver.',
              kind: NoteKind.error,
              radius: 0,
              onTap: () => _push(const SettingsScreen(openPending: true)),
            ),
          // Busca
          Container(
            color: C.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: T.sm(),
              decoration: InputDecoration(
                hintText: 'Buscar mesa...',
                hintStyle: T.sm(c: C.zinc400),
                isDense: true,
                filled: true,
                fillColor: C.zinc100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_hasComandaTables) _kindTabs(),
          _filterChips(pendingTables),
          const Divider(height: 1, thickness: 1, color: C.zinc200),
          if (_showSettings) _settingsPanel(),
          Expanded(child: _body(filtered)),
          if (store.lastFetchedAt != null)
            Padding(
              padding: EdgeInsets.only(top: 3, bottom: 3 + MediaQuery.paddingOf(context).bottom),
              child: Text('Atualizado às ${hhmmss(store.lastFetchedAt!)}', style: T.xs(c: C.zinc300)),
            ),
        ],
      ),
    );
  }

  Widget _body(List<DiningTable> filtered) {
    final store = app.tables;
    if (store.loading && store.tables.isEmpty) return const StateView(text: 'Carregando mesas...');
    if (store.error != null && store.tables.isEmpty) {
      return StateView(text: store.error!, error: true, onAction: store.fetch);
    }
    if (filtered.isEmpty) return const StateView(text: 'Nenhuma mesa encontrada.');

    final cols = app.settings.gridCols;
    final rows = (filtered.length / cols).ceil();
    final now = DateTime.now();
    return RefreshIndicator(
      color: C.primary600,
      onRefresh: store.fetch,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rows,
        itemBuilder: (context, r) {
          final slice = filtered.sublist(r * cols, ((r + 1) * cols).clamp(0, filtered.length));
          return Padding(
            padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: 12),
                    Expanded(
                      child: c < slice.length
                          ? TableCard(
                              table: slice[c],
                              cols: cols,
                              idle: idleMinutes(slice[c], store.idleAlertMinutes, now),
                              onTap: () => _onTable(slice[c]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _storeSwitcher() => Container(
    color: C.white,
    child: Column(
      children: [
        for (final s in app.auth.stores)
          Tap(
            onTap: _switching ? null : () => _switchStore(s),
            radius: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    style: s.id == app.auth.store?.id ? T.sm(w: T.semibold, c: C.primary700) : T.sm(c: C.zinc700),
                  ),
                ),
                if (s.id == app.auth.store?.id) const Icon(Icons.check, size: 16, color: C.primary600),
              ],
            ),
          ),
        const Divider(height: 1, thickness: 1, color: C.zinc200),
      ],
    ),
  );

  Widget _kindTabs() {
    final mesas = app.tables.tables.where((t) => !t.isComanda).length;
    final comandas = app.tables.tables.length - mesas;
    Widget tab(String label, int count, bool comandaTab) {
      final active = _showComandas == comandaTab;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _showComandas = comandaTab;
            _filter = 'all';
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: active ? C.primary600 : Colors.transparent, width: 2)),
            ),
            child: Text.rich(
              TextSpan(
                text: label,
                children: [TextSpan(text: ' ($count)', style: T.xs(c: active ? C.primary400 : C.zinc400))],
              ),
              textAlign: TextAlign.center,
              style: T.sm(w: T.semibold, c: active ? C.primary700 : C.zinc400),
            ),
          ),
        ),
      );
    }

    return Container(
      color: C.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [tab('Mesas', mesas, false), const SizedBox(width: 8), tab('Comandas', comandas, true)]),
    );
  }

  Widget _filterChips(int pendingTables) => Container(
    color: C.white,
    width: double.infinity,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (value, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Builder(
                builder: (_) {
                  final active = _filter == value;
                  final bg = !active
                      ? C.zinc100
                      : value == 'all'
                      ? C.primary600
                      : value == 'pending'
                      ? C.amber500
                      : tableStatusStyle(value).border;
                  return Tap(
                    onTap: () => setState(() => _filter = value),
                    color: bg,
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: T.xs(w: T.medium, c: active ? C.white : C.zinc600)),
                        if (value == 'pending' && pendingTables > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: active ? C.white : C.amber600,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('$pendingTables', style: T.s(10, w: T.bold, c: active ? C.amber700 : C.white)),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );

  Widget _settingsPanel() {
    final s = app.settings;
    final user = app.auth.user;
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t.toUpperCase(), style: T.label.copyWith(color: C.zinc400)),
    );
    return Container(
      color: C.zinc50,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('Colunas da grade'),
          Row(
            children: [
              for (final n in const [2, 3, 4]) ...[
                if (n > 2) const SizedBox(width: 8),
                Expanded(child: Choice('$n cols', selected: s.gridCols == n, solid: true, onTap: () => s.setGridCols(n))),
              ],
            ],
          ),
          const SizedBox(height: 12),
          heading('Ordenar mesas por'),
          Row(
            children: [
              for (final (i, o) in const [('number', 'Número'), ('title', 'Título'), ('status', 'Status')].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: Choice(o.$2, selected: s.sortMode == o.$1, solid: true, onTap: () => s.setSortMode(o.$1))),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Btn(
              'Impressão, maquininha e suporte',
              kind: BtnKind.outline,
              icon: Icons.tune,
              onTap: () => _push(const SettingsScreen()),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: C.zinc200)),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: C.primary600, shape: BoxShape.circle),
                    child: Text(
                      user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                      style: T.sm(w: T.bold, c: C.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(w: T.semibold)),
                        Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.xs(c: C.zinc500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(width: double.infinity, child: Btn('Sair', kind: BtnKind.dangerSoft, onTap: _logout)),
        ],
      ),
    );
  }
}

/// Card de mesa: três sinais de status (borda, barra de acento e pílula com
/// rótulo) e só o que EXISTE no atendimento — mesa livre não ganha texto.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table, required this.cols, required this.idle, this.onTap});
  final DiningTable table;
  final int cols;

  /// Minutos ociosa, ou `null`.
  final int? idle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = idle != null ? tableIdleStyle : tableStatusStyle(table.status);
    final label = idle != null ? formatIdleLabel(idle!) : st.label;
    final titleSize = cols >= 4 ? 14.0 : (cols == 3 ? 16.0 : 18.0);
    final pad = cols >= 4 ? 10.0 : (cols == 3 ? 12.0 : 16.0);
    final s = table.session;

    return Tap(
      onTap: onTap,
      color: st.bg,
      radius: 16,
      border: BorderSide(color: st.border, width: 1.5),
      splash: Colors.white24,
      padding: EdgeInsets.fromLTRB(pad, pad - 4, pad, pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de acento: leitura do status pela visão periférica.
          Container(
            height: 5,
            decoration: BoxDecoration(color: st.accent, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  table.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.s(titleSize, w: T.bold, c: st.text, h: 1.25),
                ),
              ),
              if (table.pendingCalls > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: C.amber500, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_active, size: 13, color: C.white),
                      if (table.pendingCalls > 1) Text(' ${table.pendingCalls}', style: T.s(11, w: T.bold, c: C.white)),
                    ],
                  ),
                ),
            ],
          ),
          if (table.areaName != null)
            Text(table.areaName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.xs(c: st.textMuted)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              Pill(label, bg: st.accent, fg: C.white, size: cols >= 4 ? 12 : 14),
              if (table.hasUnassignedItems) const Pill('Sem comanda', bg: C.red600, fg: C.white, size: 11),
            ],
          ),
          if (s != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 1, color: st.text.withValues(alpha: 0.2)),
            ),
            if (s.customerName != null)
              Text(s.customerName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.xs(w: T.semibold, c: st.text)),
            if (s.openedByName != null)
              Text(s.openedByName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.xs(c: st.textMuted)),
            if (s.guestCount != null && s.guestCount! > 0)
              Text('${s.guestCount} pessoa(s)', style: T.xs(c: st.textMuted)),
            Text(brl(s.total), style: T.xs(w: T.semibold, c: st.text)),
          ],
        ],
      ),
    );
  }
}
