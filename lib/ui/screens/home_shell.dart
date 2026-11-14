import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../kit.dart';
import 'cash_screen.dart';
import 'counter_screen.dart';
import 'more_screen.dart';
import 'tables_screen.dart';

/// Casca das telas raiz (seção 4 do layout novo): o menu inferior
/// `Mesas | Balcão | Caixa | Mais` e a aba aberta por cima dele.
///
///  - Mesas, Caixa e Mais são abas (o menu continua na tela);
///  - Balcão abre o fluxo de venda de balcão ([CounterScreen]) por cima, como
///    o ícone do carrinho fazia.
///
/// Também é aqui que mora o que antes ficava no mapa de mesas e vale para o
/// app inteiro: atualização periódica (sem WebSocket, que a Stone proíbe),
/// retomada ao voltar do segundo plano e reenvio dos pagamentos pendentes
/// quando a rede volta.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  MainTab _tab = MainTab.mesas;
  Timer? _tablesPoll;
  Timer? _notificationsPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.ledger.addListener(_changed);
    app.api.online.addListener(_onConnectivity);
    app.auth.refreshPermissions().then((_) => _changed());
    app.tables.fetch();
    app.methods.load();
    app.notifications.fetch();
    _startTimers();
  }

  /// A casca é a tela da frente (nenhuma outra tela aberta por cima)?
  bool get _isFront => ModalRoute.of(context)?.isCurrent ?? true;

  void _startTimers() {
    _stopTimers();
    // Mapa: mesma cadência do fallback do PWA. Cada resposta redesenha o
    // mapa, o que também atualiza a cor das mesas ociosas.
    _tablesPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isFront) app.tables.fetch();
    });
    // Sino: 30 s, enquanto o mapa ou Mais estiver na tela.
    _notificationsPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isFront && _tab != MainTab.caixa && app.api.online.value) app.notifications.fetch();
    });
  }

  void _stopTimers() {
    _tablesPoll?.cancel();
    _notificationsPoll?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.tables.fetch();
      app.menu.revalidate();
      app.notifications.fetch();
      _startTimers();
    } else if (state == AppLifecycleState.paused) {
      _stopTimers();
    }
  }

  void _onConnectivity() {
    // Voltou a rede: registra o que a maquininha cobrou e ficou pendente.
    if (app.api.online.value) app.ledger.retryAll();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.ledger.removeListener(_changed);
    app.api.online.removeListener(_onConnectivity);
    _stopTimers();
    super.dispose();
  }

  Future<void> _select(MainTab tab) async {
    FocusScope.of(context).unfocus();
    if (tab == MainTab.balcao) {
      // Mesma regra do ícone antigo: sem a permissão, o balcão não abre.
      if (!app.auth.permissions.counterSale) {
        toast(context, 'Seu usuário não tem permissão para vender no balcão.', error: true);
        return;
      }
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CounterScreen()));
      if (mounted) app.tables.fetch();
      return;
    }
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == MainTab.mesas) app.tables.fetch();
    if (tab != MainTab.caixa) app.notifications.fetch();
  }

  @override
  Widget build(BuildContext context) {
    final perms = app.auth.permissions;
    final canCash = perms.cashOpen || perms.cashClose || perms.cashMovement;
    return PopScope(
      // "Voltar" do aparelho numa aba volta para o mapa antes de sair do app.
      canPop: _tab == MainTab.mesas,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = MainTab.mesas);
      },
      child: Scaffold(
        backgroundColor: C.bg,
        // O mapa fica montado (guarda filtro e busca); Caixa e Mais são
        // recriados a cada visita e recarregam os dados ao abrir.
        body: Stack(
          children: [
            Offstage(
              offstage: _tab != MainTab.mesas,
              child: TickerMode(enabled: _tab == MainTab.mesas, child: const TablesScreen()),
            ),
            if (_tab == MainTab.caixa) CashScreen(allowed: canCash),
            if (_tab == MainTab.mais) const MoreScreen(),
          ],
        ),
        bottomNavigationBar: MainTabBar(
          current: _tab,
          onTap: _select,
          // O contador que ficava na engrenagem: pagamentos da maquininha sem registro.
          badges: {MainTab.mais: app.ledger.pending.length},
        ),
      ),
    );
  }
}
