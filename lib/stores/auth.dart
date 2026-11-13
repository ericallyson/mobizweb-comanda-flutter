import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/storage.dart';
import '../models/models.dart';

/// Sessão do operador. Espelha `stores/auth.ts` do PWA: token Sanctum
/// (ability `garcom:operate`), usuário, loja ativa e mapa de permissões.
class AuthStore extends ChangeNotifier {
  AuthStore(this._api, this._store);

  final Api _api;
  final LocalStore _store;

  String? token;
  AuthUser? user;
  StoreRef? store;
  List<StoreRef> stores = const [];
  Permissions permissions = const Permissions();

  bool get isAuthenticated => token != null;
  bool get needsStorePicker => stores.length > 1 && store == null;
  bool get hasMultipleStores => stores.length > 1;

  /// Restaura a sessão gravada no aparelho (abertura do app).
  Future<void> restore() async {
    token = await _store.readToken();
    final j = _store.getJson('auth');
    if (token == null || j == null) {
      token = null;
      return;
    }
    user = j['user'] is Map ? AuthUser.fromJson(asMap(j['user'])) : null;
    store = j['store'] is Map ? StoreRef.fromJson(asMap(j['store'])) : null;
    stores = asList(j['stores']).map(StoreRef.fromJson).toList();
    permissions = Permissions.fromJson(j['permissions']);
    _api.token = token;
  }

  /// Devolve `null` no sucesso ou a mensagem para a tela de login.
  Future<String?> login(String email, String password, {required String deviceName}) async {
    try {
      final data = await _api.post(
        '/auth/login',
        body: {'email': email.trim(), 'password': password, 'device_name': deviceName},
      );
      token = asStringOrNull(data['token']);
      if (token == null) return 'Resposta inválida do servidor.';
      user = AuthUser.fromJson(asMap(data['user']));
      stores = asList(data['stores']).map(StoreRef.fromJson).toList();
      // Loja única entra direto; com várias, o operador escolhe.
      store = stores.length == 1
          ? stores.first
          : (data['store'] is Map ? StoreRef.fromJson(asMap(data['store'])) : null);
      permissions = Permissions.fromJson(data['permissions']);
      _api.token = token;
      await _persist();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 422) return 'E-mail ou senha incorretos.';
      if (e.status == 403) return 'Usuário sem permissão para o app de comanda.';
      if (e.status == 404) return 'Loja não encontrada. Confira o endereço da loja.';
      return e.message;
    }
  }

  Future<String?> selectStore(StoreRef s) async {
    try {
      await _api.post('/stores/${s.id}/select');
      store = s;
      await _persist();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.isNetwork ? e.message : 'Não foi possível selecionar a loja. Tente novamente.';
    }
  }

  /// Recarrega as permissões (mudança de papel vale sem relogar). Silencioso.
  Future<void> refreshPermissions() async {
    if (token == null) return;
    try {
      final data = await _api.get('/auth/me');
      if (data['permissions'] is Map) {
        permissions = Permissions.fromJson(data['permissions']);
        await _persist();
        notifyListeners();
      }
    } on ApiException {
      // offline ou token inválido: o 401 já derruba a sessão pelo Api.
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } on ApiException {
      // Sem rede: o token local some de qualquer forma.
    }
    await clearLocal();
  }

  /// Encerra a sessão só no aparelho (401 do servidor ou logout).
  Future<void> clearLocal() async {
    if (token == null && user == null) return;
    token = null;
    user = null;
    store = null;
    stores = const [];
    permissions = const Permissions();
    _api.token = null;
    await _store.writeToken(null);
    await _store.setJson('auth', null);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store.writeToken(token);
    await _store.setJson('auth', {
      'user': user?.toJson(),
      'store': store?.toJson(),
      'stores': [for (final s in stores) s.toJson()],
      'permissions': permissions.toJson(),
    });
  }
}
