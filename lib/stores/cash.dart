import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Operação de caixa. 100% online (sem fila): abrir, suprimento/sangria,
/// detalhes e fechamento batem direto nos endpoints, que reusam as Actions do
/// módulo Cash (fechamento cego, caixa único etc.).
class CashStore extends ChangeNotifier {
  CashStore(this._api);

  final Api _api;

  CashContext? context;
  CashDetail? detail;
  bool loading = false;
  String? error;

  CashSession? get session => context?.session;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      context = CashContext.fromJson(await _api.get('/cash'));
      final s = context?.session;
      detail = null;
      if (s != null) await fetchSummary(s.id, notify: false);
    } on ApiException catch (e) {
      error = e.isNetwork ? 'A operação de caixa exige conexão. Reconecte para continuar.' : e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<CashDetail?> fetchSummary(String sessionId, {bool notify = true}) async {
    try {
      detail = CashDetail.fromJson(await _api.get('/cash/sessions/$sessionId/summary'));
      return detail;
    } on ApiException catch (e) {
      error = e.message;
      return null;
    } finally {
      if (notify) notifyListeners();
    }
  }

  Future<String?> open(double openingAmount, {String? notes}) async {
    try {
      final data = await _api.post('/cash/open', body: {'opening_amount': openingAmount, 'notes': ?notes});
      context = (context ?? const CashContext(enabled: true)).withSession(CashSession.fromJson(asMap(data['session'])));
      final s = context?.session;
      if (s != null) await fetchSummary(s.id, notify: false);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// `type`: `supply` (suprimento) | `withdrawal` (sangria).
  Future<String?> movement(String type, double amount, String reason) async {
    final s = session;
    if (s == null) return 'Nenhum caixa aberto.';
    try {
      await _api.post('/cash/sessions/${s.id}/movements', body: {'type': type, 'amount': amount, 'reason': reason});
      await fetchSummary(s.id);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// `breakdown`: valor contado por forma de pagamento (chave canônica).
  Future<String?> close(Map<String, double> breakdown, {String? notes}) async {
    final s = session;
    if (s == null) return 'Nenhum caixa aberto.';
    try {
      await _api.post(
        '/cash/sessions/${s.id}/close',
        body: {'closing_breakdown': breakdown, if (notes != null && notes.isNotEmpty) 'notes': notes},
      );
      context = context?.withSession(null);
      detail = null;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  void reset() {
    context = null;
    detail = null;
    loading = false;
    error = null;
    notifyListeners();
  }
}
