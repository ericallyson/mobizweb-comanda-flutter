import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../kit.dart';

/// Escolha da loja (operador vinculado a mais de uma).
class StorePickerScreen extends StatefulWidget {
  const StorePickerScreen({super.key});

  @override
  State<StorePickerScreen> createState() => _StorePickerScreenState();
}

class _StorePickerScreenState extends State<StorePickerScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _pick(StoreRef store) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await app.auth.selectStore(store);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }
    app.menu.fetch();
    app.methods.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = app.auth;
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
                  Text('Selecione a loja', style: T.sm(w: T.medium, c: C.primary200)),
                  const SizedBox(height: 28),
                  Text.rich(
                    TextSpan(
                      text: 'Olá, ',
                      children: [
                        TextSpan(text: auth.user?.name ?? '', style: T.sm(w: T.bold, c: C.white)),
                        const TextSpan(text: '. Escolha a loja:'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: T.sm(c: C.primary200),
                  ),
                  const SizedBox(height: 12),
                  if (auth.stores.isEmpty)
                    const Note('Seu usuário não está vinculado a nenhuma loja ativa.', kind: NoteKind.error),
                  for (final s in auth.stores)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Opacity(
                        opacity: _loading ? 0.6 : 1,
                        child: Tap(
                          onTap: _loading ? null : () => _pick(s),
                          color: C.white,
                          radius: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Expanded(child: Text(s.name, style: T.base(w: T.semibold, c: C.primary700))),
                              const Icon(Icons.chevron_right, color: C.primary300),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error != null) Note(_error!, kind: NoteKind.error),
                  const SizedBox(height: 8),
                  Tap(
                    onTap: _loading ? null : () => app.auth.logout(),
                    radius: 8,
                    splash: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text('Sair', style: T.sm(w: T.medium, c: C.primary200)),
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
