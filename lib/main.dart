import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'ui/kit.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/store_picker_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await App.boot();
  app.terminal.onPreview = previewPrint;
  runApp(const MobizApp());
}

/// Modo demonstração: mostra na tela o que iria para a bobina.
Future<void> previewPrint(List<Uint8List> pngs) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  await showSheet<void>(
    ctx,
    (c) => SheetBody(
      title: 'Prévia da impressão',
      subtitle: 'Modo demonstração: nada foi impresso.',
      children: [
        Container(
          color: C.zinc100,
          padding: const EdgeInsets.all(12),
          child: Column(children: [for (final p in pngs) Image.memory(p, filterQuality: FilterQuality.none)]),
        ),
      ],
      footer: Btn('Fechar', kind: BtnKind.secondary, onTap: () => Navigator.pop(c)),
    ),
  );
}

class MobizApp extends StatelessWidget {
  const MobizApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mobiz POS',
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // O texto do sistema não pode estourar os cards em maquininha de tela
    // pequena: a escala de fonte fica entre 0,9 e 1,15.
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.15,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const RootGate(),
  );
}

/// Decide a tela raiz pelo estado da sessão: login → escolha de loja → casca
/// com o menu inferior (mesas).
/// Quando o servidor revoga o token (401), volta sozinho para o login.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _wasAuthenticated = app.auth.isAuthenticated;

  @override
  void initState() {
    super.initState();
    app.auth.addListener(_onAuth);
  }

  @override
  void dispose() {
    app.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final now = app.auth.isAuthenticated;
    if (_wasAuthenticated && !now) {
      // Sessão encerrada: fecha tudo que estiver por cima e limpa os dados.
      app.resetDomain();
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    _wasAuthenticated = now;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = app.auth;
    if (!auth.isAuthenticated) return const LoginScreen();
    if (auth.store == null) return const StorePickerScreen();
    return const HomeShell();
  }
}
