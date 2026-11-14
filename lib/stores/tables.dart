import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/format.dart';
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
          error = e.isNetwork ? 'Sem conexão. Os dados não estão disponíveis.' : 'Não foi possível carregar as mesas.';
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

// ── Filtros e busca do mapa (só leitura dos dados de `GET /tables`) ──────────

/// Em que chip de filtro a mesa cai. Os grupos são EXCLUSIVOS e seguem a cor
/// do card: mesa "ocupada" que passou do limite de ociosidade conta em
/// `idle`, não em `occupied`.
enum TableFilter { all, available, occupied, closing, idle, reserved, pending }

/// Grupo de cor/status da mesa (nunca `all` nem `pending`).
TableFilter tableGroup(DiningTable table, int idleLimitMinutes, DateTime now) {
  if (idleMinutes(table, idleLimitMinutes, now) != null) return TableFilter.idle;
  return switch (table.status) {
    'occupied' => TableFilter.occupied,
    'closing' => TableFilter.closing,
    'reserved' => TableFilter.reserved,
    _ => TableFilter.available,
  };
}

bool tableMatchesFilter(DiningTable table, TableFilter filter, int idleLimitMinutes, DateTime now) => switch (filter) {
  TableFilter.all => true,
  TableFilter.pending => table.pendingCalls > 0,
  _ => tableGroup(table, idleLimitMinutes, now) == filter,
};

/// Contagem de cada chip: `all` = todas; `pending` = mesas com chamado (pode
/// repetir mesa de outro grupo); os demais somam `all`.
Map<TableFilter, int> countTablesByFilter(Iterable<DiningTable> tables, int idleLimitMinutes, DateTime now) {
  final counts = {for (final f in TableFilter.values) f: 0};
  for (final t in tables) {
    counts[TableFilter.all] = counts[TableFilter.all]! + 1;
    final g = tableGroup(t, idleLimitMinutes, now);
    counts[g] = counts[g]! + 1;
    if (t.pendingCalls > 0) counts[TableFilter.pending] = counts[TableFilter.pending]! + 1;
  }
  return counts;
}

/// Número da mesa sem o prefixo "Mesa": `Mesa 12` → `12`.
String tableNumberKey(DiningTable t) => t.number.replaceFirst(RegExp(r'^mesa\s*', caseSensitive: false), '').trim();

/// A busca "enquanto digita" do mapa: pelo título ou pelo número.
bool tableMatchesQuery(DiningTable t, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty || t.title.toLowerCase().contains(q) || t.number.toLowerCase().contains(q);
}

/// O botão "Entrar": a mesa ou comanda cujo número (ou título) é EXATAMENTE o
/// digitado ("12", "mesa 12", "Comanda 101"). Parecido não vale: "1" não abre
/// a mesa 10. `preferComanda` desempata quando existe mesa e comanda com o
/// mesmo número (vale a aba aberta). `null` = não existe.
DiningTable? findTableForEntry(List<DiningTable> tables, String query, {bool preferComanda = false}) {
  final q = fold(query.trim());
  if (q.isEmpty) return null;
  final key = q.replaceFirst(RegExp(r'^(mesa|comanda)\s*'), '');
  bool exact(DiningTable t) => fold(tableNumberKey(t)) == key || fold(t.number) == q || fold(t.title) == q;
  final hits = tables.where(exact).toList();
  if (hits.isEmpty) return null;
  return hits.where((t) => t.isComanda == preferComanda).firstOrNull ?? hits.first;
}
