import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../kit.dart';
import 'settings_screen.dart';

/// Login do operador. Igual ao do PWA, com um campo a mais: o endereço da
/// loja — no navegador ele vem da URL; no app o operador informa uma vez e
/// fica gravado no aparelho.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _server = TextEditingController(text: app.settings.serverInput);
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  late bool _editServer = app.settings.serverInput.isEmpty;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final url = normalizeServerUrl(_server.text, defaultDomain: Config.defaultDomain);
    if (url.isEmpty) {
      setState(() {
        _error = 'Informe o endereço da loja.';
        _editServer = true;
      });
      return;
    }
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Informe e-mail e senha.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    app.settings.setServerInput(_server.text);
    app.api.baseUrl = app.settings.serverUrl;
    final error = await app.auth.login(_email.text, _password.text, deviceName: app.deviceName);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
        if (error.startsWith('Loja não encontrada')) _editServer = true;
      });
      return;
    }
    // Deixa o cardápio pronto antes de abrir a primeira comanda. A raiz
    // (RootGate) troca de tela sozinha quando a sessão muda.
    if (app.auth.store != null) {
      app.menu.fetch();
      app.methods.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(normalizeServerUrl(_server.text, defaultDomain: Config.defaultDomain))?.host ?? '';
    return Scaffold(
      backgroundColor: C.primary600,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Mobiz', style: T.s(30, w: T.black, c: C.white, h: 1.2)),
                  Text('Comanda · PDV', style: T.sm(w: T.medium, c: C.primary200)),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: C.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Entrar', style: T.lg(w: T.bold, c: C.primary700)),
                          const SizedBox(height: 14),
                          if (_editServer) ...[
                            Field(
                              label: 'Endereço da loja',
                              controller: _server,
                              hint: 'minhaloja',
                              keyboard: TextInputType.url,
                              action: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 12),
                              child: Text(
                                host.isEmpty
                                    ? 'O mesmo endereço que você usa no navegador.'
                                    : 'Conecta em $host',
                                style: T.s(11, c: C.zinc400),
                              ),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Tap(
                                onTap: () => setState(() => _editServer = true),
                                color: C.zinc50,
                                radius: 8,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.storefront_outlined, size: 16, color: C.zinc500),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.xs(w: T.medium, c: C.zinc600)),
                                    ),
                                    Text('trocar', style: T.xs(w: T.semibold, c: C.primary500)),
                                  ],
                                ),
                              ),
                            ),
                          Field(
                            label: 'E-mail',
                            controller: _email,
                            hint: 'garcom@restaurante.com',
                            keyboard: TextInputType.emailAddress,
                            action: TextInputAction.next,
                            autofill: const [AutofillHints.username],
                          ),
                          const SizedBox(height: 14),
                          Field(
                            label: 'Senha',
                            controller: _password,
                            hint: '••••••••',
                            obscure: true,
                            action: TextInputAction.done,
                            autofill: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 14),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Note(_error!, kind: NoteKind.error, center: false),
                            ),
                          Btn(_loading ? 'Entrando...' : 'Entrar', kind: BtnKind.accent, loading: _loading, onTap: _submit),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Tap(
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                    radius: 8,
                    splash: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text('Configurações do aparelho · Fale conosco', style: T.xs(w: T.medium, c: C.primary200)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
