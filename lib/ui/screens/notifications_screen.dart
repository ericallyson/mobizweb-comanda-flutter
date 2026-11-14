import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../stores/notifications.dart';
import '../kit.dart';
import 'session_screen.dart';

/// Abre Notificações por cima da tela atual (mapa ou Mais); "voltar" retorna
/// para ela. Tocar num chamado fecha a lista e abre a mesa que chamou, como o
/// sino do PWA.
Future<void> openNotifications(BuildContext context) async {
  FocusScope.of(context).unfocus();
  final tableId = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  if (tableId == null || !context.mounted) return;
  final table = app.tables.tables.where((t) => t.id == tableId).firstOrNull;
  final session = table?.session;
  if (table == null || session == null) {
    toast(context, 'Esta mesa não tem atendimento aberto.');
    return;
  }
  app.session.clear();
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SessionScreen(sessionId: session.id, title: table.title),
    ),
  );
  app.tables.fetch();
}

/// Notificações (seção 5.9), a mesma lista do `NotificationCenter.vue` do
/// PWA, em cartões brancos:
///  - chamados do tablet ("Estou indo" / "Atendida");
///  - pedidos do tablet aguardando liberação ("Liberar");
///  - estoque crítico (informativo: produto, quantidade e mínimo).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Timer? _clock;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    app.notifications.addListener(_changed);
    // Depois do primeiro quadro: o aviso do store redesenha as telas de baixo
    // (mapa, Mais), o que não pode acontecer no meio da montagem desta.
    Future.microtask(app.notifications.fetch);
    // O "há X min" anda na tela sem precisar de resposta do servidor.
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => _changed());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (app.api.online.value) app.notifications.fetch();
    });
  }

  @override
  void dispose() {
    app.notifications.removeListener(_changed);
    _clock?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<String?> Function() action, [String? done]) async {
    final error = await action();
    if (!mounted) return;
    if (error != null) {
      toast(context, error, error: true);
    } else if (done != null) {
      toast(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = app.notifications;
    final now = DateTime.now();

    Widget body;
    if (!n.loaded && n.loading) {
      body = const StateView(text: 'Carregando notificações...');
    } else if (n.isEmpty) {
      body = RefreshIndicator(
        color: C.navy,
        onRefresh: n.fetch,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: box.maxHeight,
              child: StateView(
                icon: Icons.notifications_off_outlined,
                text: n.loaded ? 'Nenhuma solicitação pendente.' : 'Não foi possível carregar as notificações.',
                onAction: n.loaded ? null : n.fetch,
              ),
            ),
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        color: C.navy,
        onRefresh: n.fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(14, 14, 14, 14 + MediaQuery.paddingOf(context).bottom),
          children: [
            if (n.calls.isNotEmpty) ...[
              SectionLabel('Chamados das mesas', trailing: Tag('${n.calls.length}')),
              _card([for (final c in n.calls) _callRow(c, n, now)]),
            ],
            if (n.pendingOrders.isNotEmpty) ...[
              SectionLabel('Pedidos do tablet', trailing: Tag('${n.pendingOrders.length}')),
              _card([for (final o in n.pendingOrders) _orderRow(o, n, now)]),
            ],
            if (n.lowStockAlerts.isNotEmpty) ...[
              SectionLabel('Estoque crítico', trailing: Tag('${n.lowStockAlerts.length}')),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                child: Text('Abaixo do mínimo nesta loja. Avise o gerente.', style: T.s(12.5, c: C.sub, h: 1.35)),
              ),
              _card([for (final a in n.lowStockAlerts) _stockRow(a)]),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          AppHeader(title: 'Notificações', subtitle: app.auth.store?.name, onBack: () => Navigator.pop(context)),
          if (!app.api.online.value)
            const Note('Sem conexão com o servidor. A lista pode estar desatualizada.', radius: 0),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// Cartão branco com as linhas separadas por divisória.
  Widget _card(List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: CardBox(
      padding: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(height: 1, thickness: 1, color: C.line),
                  ),
                r,
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _smallBtn(String label, {required VoidCallback onTap, bool filled = false, IconData? icon}) => Tap(
    onTap: onTap,
    color: filled ? C.green : C.bg,
    radius: 10,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: filled ? C.white : C.ink), const SizedBox(width: 4)],
            Text(
              label,
              style: T.s(12, w: T.bold, c: filled ? C.white : C.ink, h: 1.2),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _callRow(TabletCall c, NotificationsStore n, DateTime now) {
    final late = isLateCall(c.elapsedSeconds, n.fetchedAt, now);
    final when = [
      if (hhmm(c.createdAt).isNotEmpty) hhmm(c.createdAt),
      elapsedLabel(c.elapsedSeconds, n.fetchedAt, now),
      if (c.isAcknowledged) 'a caminho',
    ].join(' · ');
    return Container(
      color: late ? C.amber50 : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, c.tableId),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.tableLabel, style: T.body(w: T.bold)),
                    Text(c.reasonLabel, style: T.body(c: C.ink, size: 13.5)),
                    if (c.note != null)
                      Text(
                        '"${c.note}"',
                        style: T.s(12, c: C.sub, h: 1.35).copyWith(fontStyle: FontStyle.italic),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: T.num(12, w: T.medium, c: late ? C.amber800 : C.sub, h: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!c.isAcknowledged) ...[
                _smallBtn('Estou indo', onTap: () => _run(() => n.acknowledge(c.id))),
                const SizedBox(height: 6),
              ],
              _smallBtn('Atendida', filled: true, icon: Icons.check, onTap: () => _run(() => n.resolve(c.id))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderRow(TabletOrderNotice o, NotificationsStore n, DateTime now) {
    final when = [
      if (hhmm(o.createdAt).isNotEmpty) hhmm(o.createdAt),
      elapsedLabel(o.elapsedSeconds, n.fetchedAt, now),
      'aguardando liberação',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.tableLabel.isEmpty ? 'Mesa' : o.tableLabel, style: T.body(w: T.bold)),
                Text(
                  o.items.map((i) => '${qty(i.quantity)}× ${i.name}').join(', '),
                  style: T.body(c: C.ink, size: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  when,
                  style: T.num(12, w: T.medium, c: C.sub, h: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _smallBtn(
            'Liberar',
            filled: true,
            onTap: () => _run(() => n.approveOrder(o.id), 'Pedido liberado para a cozinha'),
          ),
        ],
      ),
    );
  }

  Widget _stockRow(LowStockAlert a) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            a.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body(w: T.semibold),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${qty(a.currentStock)} ${a.unit}', style: T.num(14, c: C.cancel)),
            Text(
              'mínimo ${qty(a.minStock)} ${a.unit}',
              style: T.num(11.5, w: FontWeight.w400, c: C.sub),
            ),
          ],
        ),
      ],
    ),
  );
}
