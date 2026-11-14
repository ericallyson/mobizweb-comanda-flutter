import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../kit.dart';
import '../sheets/comanda_link_sheet.dart';
import '../sheets/store_switch_sheet.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

/// Mais (seção 5.9 do layout novo): o que saiu do topo antigo do mapa e não
/// virou aba. Cada linha chama a mesma rotina do ícone que substitui. É uma
/// ABA da [HomeShell] (sem `Scaffold` próprio).
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    app.notifications.addListener(_changed);
    app.ledger.addListener(_changed);
    app.auth.addListener(_changed);
  }

  @override
  void dispose() {
    app.notifications.removeListener(_changed);
    app.ledger.removeListener(_changed);
    app.auth.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// "Atualizar": o que o ícone de atualizar do mapa fazia (recarrega as
  /// mesas), mais o cardápio e o sino, que o app já revalida ao voltar do
  /// segundo plano.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await Future.wait([app.tables.fetch(), app.menu.revalidate(), app.notifications.fetch()]);
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (app.api.online.value) {
      toast(context, 'Mesas e cardápio atualizados');
    } else {
      toast(context, 'Sem conexão com o servidor. Tente de novo em instantes.', error: true);
    }
  }

  Future<void> _linkComanda() => showSheet<void>(context, (_) => const ComandaLinkSheet());

  Future<void> _settings() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(openPending: app.ledger.pending.isNotEmpty)),
  );

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

  @override
  Widget build(BuildContext context) {
    final auth = app.auth;
    final user = auth.user;
    final notifications = app.notifications.count;
    final pendingTef = app.ledger.pending.length;
    final who = [
      if (user != null && user.name.trim().isNotEmpty) 'Garçom ${user.name.trim()}',
      ?auth.store?.name,
    ].join(' · ');

    return ColoredBox(
      color: C.bg,
      child: Column(
        children: [
          AppHeader(title: 'Mais', subtitle: who),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                CardBox(
                  padding: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          MenuRow(
                            icon: Icons.notifications_none,
                            label: 'Notificações',
                            trailing: notifications > 0 ? CountBadge(notifications) : null,
                            onTap: () => openNotifications(context),
                          ),
                          MenuRow(icon: Icons.qr_code_2, label: 'Ler QR da comanda', onTap: _linkComanda),
                          MenuRow(
                            icon: Icons.sync,
                            label: 'Atualizar',
                            trailing: _refreshing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: C.navy),
                                  )
                                : null,
                            onTap: _refreshing ? null : _refresh,
                          ),
                          MenuRow(
                            icon: Icons.storefront_outlined,
                            label: 'Trocar loja',
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                auth.store?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.s(12.5, w: T.medium, c: C.sub, h: 1.3),
                              ),
                            ),
                            onTap: () => showStoreSwitch(context),
                          ),
                          MenuRow(
                            icon: Icons.settings_outlined,
                            label: 'Configurações',
                            trailing: pendingTef > 0 ? CountBadge(pendingTef) : null,
                            onTap: _settings,
                            last: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (user != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Conectado como ${user.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.s(12, c: C.sub, h: 1.3),
                    ),
                  ),
                Tap(
                  onTap: _logout,
                  color: C.white,
                  radius: 14,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 46),
                    child: Center(
                      child: Text(
                        'Sair',
                        style: T.s(13, w: T.bold, c: C.cancel, h: 1.2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
