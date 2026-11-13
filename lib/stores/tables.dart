import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/storage.dart';
import '../models/models.dart';

/// Mapa de mesas da loja ativa (`GET /tables`), com cache para abrir o app
/// sem rede. Espelha `stores/tables.ts` do PWA.
class TablesStore extends ChangeNotifier {
  TablesStore(this._api, this._store);

  final Api _api;
  final LocalStore _store;

  List<DiningTable> tables = const [];
  bool loading = false;
  String? error;
  DateTime? lastFetchedAt;

  /// `tables_settings.enable_comandas` da loja.
  bool enableComandas = true;

  /// Alerta de mesa ociosa em minutos; 0 = desligado.
  int idleAlertMinutes = 0;

  /// A última leitura veio do cache (sem rede)?
  bool fromCache = false;

  Future<void> fetch() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.get('/tables');
      _apply(data);
      fromCache = false;
      lastFetchedAt = DateTime.now();
      _store.writeCache('tables', {'data': data, 'at': lastFetchedAt!.millisecondsSinceEpoch});
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // sessão caiu: o Api já avisou o AuthStore.
      } else if (tables.isEmpty) {
        final cached = await _store.readCache('tables');
        if (cached is Map && cached['data'] is Map) {
          _apply(asMap(cached['data']));
          fromCache = true;
          lastFetchedAt = DateTime.fromMillisecondsSinceEpoch(asInt(cached['at']));
        } else {
          error = e.isNetwork ? 'Sem conexão — dados não disponíveis.' : 'Não foi possível carregar as mesas.';
        }
      } else {
        fromCache = e.isNetwork;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _apply(Json data) {
    tables = asList(data['tables']).map(DiningTable.fromJson).toList();
    final settings = asMap(data['settings']);
    enableComandas = asBool(settings['enable_comandas'], true);
    idleAlertMinutes = asInt(settings['idle_alert_minutes']).clamp(0, 100000);
  }

  /// Abre a mesa. Devolve o id da sessão ou lança [ApiException].
  Future<String> open(DiningTable table, {int? guestCount, String? customerName, List<String> comandas = const []}) async {
    final data = await _api.post(
      '/tables/${table.id}/sessions',
      body: {
        'guest_count': ?guestCount,
        'customer_name': ?customerName,
        if (comandas.isNotEmpty) 'comandas': comandas,
      },
    );
    return asString(asMap(data['session'])['id']);
  }

  void reset() {
    tables = const [];
    loading = false;
    error = null;
    lastFetchedAt = null;
    fromCache = false;
    notifyListeners();
  }
}

/// Minutos sem lançamento quando a mesa está OCIOSA; `null` quando não está.
/// Mesma regra de `lib/tableIdle.ts`: só mesa "ocupada", limite > 0 e
/// agora − último lançamento ≥ limite.
int? idleMinutes(DiningTable table, int limitMinutes, DateTime now) {
  if (limitMinutes <= 0) return null;
  if (table.status != 'occupied') return null;
  final raw = table.session?.lastActivityAt;
  if (raw == null) return null;
  final at = DateTime.tryParse(raw);
  if (at == null) return null;
  final diff = now.difference(at).inMinutes;
  final minutes = diff < 0 ? 0 : diff;
  return minutes >= limitMinutes ? minutes : null;
}

/// "Ociosa · 25 min" / "Ociosa · 1h" / "Ociosa · 2h05".
String formatIdleLabel(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  if (m < 60) return 'Ociosa · $m min';
  final h = m ~/ 60;
  final rem = m % 60;
  return rem > 0 ? 'Ociosa · ${h}h${rem.toString().padLeft(2, '0')}' : 'Ociosa · ${h}h';
}
