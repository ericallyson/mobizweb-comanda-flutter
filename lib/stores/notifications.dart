import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Central de notificações do garçom (o sino). Espelha
/// `stores/notifications.ts` do PWA, com os mesmos endpoints:
///
///  - `GET  /tablet/calls`                 chamados, pedidos do tablet e estoque crítico;
///  - `POST /tablet/calls/{id}/ack`        "Estou indo";
///  - `POST /tablet/calls/{id}/resolve`    "Atendida";
///  - `POST /tablet/orders/{id}/approve`   "Liberar" pedido do tablet.
///
/// Sem WebSocket (a Stone proíbe): quem mostra o sino chama [fetch] a cada
/// 30 s, o mesmo fallback do PWA.
class NotificationsStore extends ChangeNotifier {
  NotificationsStore(this._api);

  final Api _api;

  List<TabletCall> calls = const [];
  List<TabletOrderNotice> pendingOrders = const [];

  /// table_id → nº de pendências.
  Map<String, int> pendingByTable = const {};

  /// Itens abaixo do mínimo na loja ativa, os mais críticos primeiro.
  List<LowStockAlert> lowStockAlerts = const [];
  bool loading = false;

  /// A primeira resposta já chegou (para a tela não dizer "nenhuma" antes).
  bool loaded = false;

  /// Momento da última resposta: base do "há X min".
  DateTime fetchedAt = DateTime.now();

  /// O número do sino: SÓ o que alguém pode resolver dali (chamados e pedidos
  /// aguardando liberação). Estoque crítico fica de fora, como no PWA.
  int get count => calls.length + pendingOrders.length;

  bool get isEmpty => count == 0 && lowStockAlerts.isEmpty;

  int pendingFor(String tableId) => pendingByTable[tableId] ?? 0;

  Future<void> fetch() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final data = await _api.get('/tablet/calls');
      calls = asList(data['calls']).map(TabletCall.fromJson).toList();
      pendingOrders = asList(data['pending_orders']).map(TabletOrderNotice.fromJson).toList();
      pendingByTable = {for (final e in asMap(data['pending_by_table']).entries) e.key: asInt(e.value)};
      // Servidor antigo não manda o campo: lista vazia.
      lowStockAlerts = asList(data['low_stock_alerts']).map(LowStockAlert.fromJson).toList();
      fetchedAt = DateTime.now();
      loaded = true;
    } on ApiException {
      // Sem rede ou sem permissão: mantém o que já estava na tela.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// "Estou indo". Otimista; se o servidor recusar, recarrega e devolve a
  /// mensagem para a tela.
  Future<String?> acknowledge(String id) async {
    calls = [for (final c in calls) c.id == id ? c.acknowledged() : c];
    notifyListeners();
    return _mutate('/tablet/calls/$id/ack');
  }

  /// "Atendida": sai da lista e o sino diminui.
  Future<String?> resolve(String id) async {
    final call = calls.where((c) => c.id == id).firstOrNull;
    calls = calls.where((c) => c.id != id).toList();
    if (call != null) {
      final left = (pendingByTable[call.tableId] ?? 1) - 1;
      pendingByTable = {...pendingByTable, call.tableId: left < 0 ? 0 : left};
    }
    notifyListeners();
    return _mutate('/tablet/calls/$id/resolve');
  }

  /// Libera para a cozinha um pedido feito no tablet.
  Future<String?> approveOrder(String id) async {
    pendingOrders = pendingOrders.where((o) => o.id != id).toList();
    notifyListeners();
    return _mutate('/tablet/orders/$id/approve');
  }

  Future<String?> _mutate(String path) async {
    try {
      await _api.post(path);
      return null;
    } on ApiException catch (e) {
      await fetch();
      return Api.reasonOf(e.body) ?? e.message;
    }
  }

  void reset() {
    calls = const [];
    pendingOrders = const [];
    pendingByTable = const {};
    lowStockAlerts = const [];
    loading = false;
    loaded = false;
    notifyListeners();
  }
}

/// "há 40s" / "há 4 min" / "há 1h05": decorrido informado pelo servidor mais
/// o tempo que passou no aparelho desde a resposta.
String elapsedLabel(int baseSeconds, DateTime fetchedAt, DateTime now) {
  final drift = now.difference(fetchedAt).inSeconds;
  final total = baseSeconds + drift < 0 ? 0 : baseSeconds + drift;
  if (total < 60) return 'há ${total}s';
  final minutes = total ~/ 60;
  if (minutes < 60) return 'há $minutes min';
  return 'há ${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Passou de 5 min sem ninguém atender: o chamado fica em destaque.
bool isLateCall(int baseSeconds, DateTime fetchedAt, DateTime now) =>
    baseSeconds + now.difference(fetchedAt).inSeconds >= 300;
