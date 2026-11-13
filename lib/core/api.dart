import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'uuid.dart';

/// Falha de chamada à API, já classificada para a tela.
class ApiException implements Exception {
  ApiException({this.status, required this.message, this.body = const {}});

  /// `null` = sem resposta (rede, DNS, timeout).
  final int? status;
  final String message;
  final Json body;

  bool get isNetwork => status == null;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isValidation => status == 422;

  /// Loja operada pelo MobizHíbrido (hub local): a nuvem recusa mutações.
  bool get isHybridLocked => status == 423;

  /// Rede/timeout/5xx: vale tentar de novo com a MESMA Idempotency-Key.
  bool get isTransient => status == null || status! >= 500 || status == 409;

  @override
  String toString() => message;
}

/// Converte o endereço digitado ("minhaloja", "minhaloja.mobizweb.com.br",
/// "https://…") na origem do tenant. O tenant é resolvido pelo SUBDOMÍNIO
/// (Stancl) — não existe header de tenant.
String normalizeServerUrl(String raw, {required String defaultDomain}) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return '';
  var scheme = 'https';
  final m = RegExp(r'^(https?)://').firstMatch(s);
  if (m != null) {
    scheme = m.group(1)!;
    s = s.substring(m.end);
  }
  s = s.split('/').first;
  if (s.isEmpty) return '';
  if (!s.contains('.') && !s.contains(':')) s = '$s.$defaultDomain';
  return '$scheme://$s';
}

/// Cliente HTTP de `/api/garcom/v1`. Espelha `apps/garcom-pwa/src/lib/http.ts`:
/// Bearer do Sanctum, `Accept: application/json` (sem ele o backend responde
/// HTML/redirect) e `Idempotency-Key` em toda mutação.
class Api {
  Api({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Origem do tenant, ex.: `https://minhaloja.mobizweb.com.br`.
  String baseUrl = '';
  String? token;

  /// Chamado em 401 (token revogado): a sessão local é encerrada.
  void Function()? onUnauthorized;

  /// `false` depois de uma chamada sem resposta; volta a `true` na próxima
  /// que responder. Alimenta o aviso "Sem conexão" das telas.
  final ValueNotifier<bool> online = ValueNotifier(true);

  static const _timeout = Duration(seconds: 15);
  static const _prefix = '/api/garcom/v1';

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$_prefix$path').replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  Map<String, String> _headers({String? idempotencyKey, bool json = false}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
    'Idempotency-Key': ?idempotencyKey,
  };

  Future<Json> get(String path, {Map<String, String>? query, Duration? timeout}) =>
      _send('GET', path, query: query, timeout: timeout);

  /// `idempotencyKey` deve ser ESTÁVEL por operação quando houver retry
  /// (carrinho, transação TEF). Sem informar, gera uma nova por chamada.
  Future<Json> post(String path, {Json? body, String? idempotencyKey}) =>
      _send('POST', path, body: body ?? const {}, idempotencyKey: idempotencyKey ?? uuidV7());

  Future<Json> patch(String path, {Json? body, String? idempotencyKey}) =>
      _send('PATCH', path, body: body ?? const {}, idempotencyKey: idempotencyKey ?? uuidV7());

  Future<Json> delete(String path, {Json? body, String? idempotencyKey}) =>
      _send('DELETE', path, body: body, idempotencyKey: idempotencyKey ?? uuidV7());

  Future<Json> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Json? body,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    if (baseUrl.isEmpty) {
      throw ApiException(message: 'Endereço da loja não configurado.');
    }
    final req = http.Request(method, _uri(path, query));
    req.headers.addAll(_headers(idempotencyKey: idempotencyKey, json: body != null));
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      final streamed = await _client.send(req).timeout(timeout ?? _timeout);
      res = await http.Response.fromStream(streamed).timeout(timeout ?? _timeout);
    } on TimeoutException {
      online.value = false;
      throw ApiException(message: 'O servidor demorou para responder. Verifique a conexão.');
    } on HandshakeException {
      online.value = false;
      throw ApiException(message: 'Falha de segurança (TLS) ao conectar no servidor.');
    } on SocketException {
      online.value = false;
      throw ApiException(message: 'Sem conexão com o servidor. Verifique a internet do aparelho.');
    } on http.ClientException {
      online.value = false;
      throw ApiException(message: 'Sem conexão com o servidor. Verifique a internet do aparelho.');
    }
    online.value = true;

    Json data = const {};
    if (res.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map) data = decoded.cast<String, dynamic>();
      } catch (_) {
        // Corpo não-JSON (HTML de erro do proxy etc.): fica vazio.
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(status: res.statusCode, message: _messageFor(res.statusCode, data), body: data);
  }

  /// Primeira mensagem legível do corpo de erro: `errors.stock` (guarda de
  /// estoque) > `error` > `errors.*` > `message`.
  static String? reasonOf(Json data) {
    String? first(dynamic v) {
      final t = v is List ? (v.isEmpty ? null : v.first) : v;
      return (t is String && t.trim().isNotEmpty) ? t.trim() : null;
    }

    final errors = data['errors'] is Map ? asMap(data['errors']) : null;
    return first(errors?['stock']) ??
        first(data['error']) ??
        errors?.values.map(first).firstWhere((m) => m != null, orElse: () => null) ??
        first(data['message']);
  }

  static String _messageFor(int status, Json data) {
    final reason = reasonOf(data);
    switch (status) {
      case 401:
        return 'Sessão expirada. Entre novamente.';
      case 403:
        return reason ?? 'Seu usuário não tem permissão para esta ação.';
      case 404:
        return reason ?? 'Registro não encontrado.';
      case 409:
        return 'Requisição em processamento. Aguarde e tente de novo.';
      case 422:
        return reason ?? 'Não foi possível concluir a operação.';
      case 423:
        return reason ?? 'Esta loja opera pelo servidor local (MobizHíbrido).';
      default:
        return status >= 500
            ? 'Erro no servidor ($status). Tente novamente em instantes.'
            : (reason ?? 'Erro inesperado ($status).');
    }
  }
}
