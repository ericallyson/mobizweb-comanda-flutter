import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/api.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/stone/stone_deeplink.dart';
import 'package:mobizweb_pos/stores/payments.dart';

const _channel = MethodChannel('mobiz/native');

const _approved =
    'mobizpos://pay-response?code=0&amount=4070&atk=37820073187607&authorization_code=187607'
    '&brand=MASTERCARD&pan=627303****2166&type=Cr%C3%A9dito';

/// Sobe o app com armazenamento em memória, HTTP falso e uma maquininha falsa
/// (canal nativo) que responde `stoneReturn` ao deeplink de pagamento.
Future<({App app, MemoryBackend backend, List<http.Request> requests, List<String> launched})> _boot({
  required http.Response Function(http.Request) respond,
  String? stoneReturn,
  String? orphan,
  MemoryBackend? backend,
}) async {
  final requests = <http.Request>[];
  final launched = <String>[];
  var pendingOrphan = orphan;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    switch (call.method) {
      case 'launch':
        launched.add((call.arguments as Map)['uri'] as String);
        if (stoneReturn == null) throw PlatformException(code: 'abandoned');
        return stoneReturn;
      case 'takeOrphan':
        final o = pendingOrphan;
        pendingOrphan = null;
        return o;
      default:
        return null;
    }
  });
  final b = backend ?? MemoryBackend();
  b.values['server_input'] = 'loja';
  final app = await App.boot(
    backend: b,
    client: MockClient((req) async {
      requests.add(req);
      return respond(req);
    }),
    probeDevice: false,
  );
  app.terminal.stoneAvailable = true;
  await app.ledger.init();
  return (app: app, backend: b, requests: requests, launched: launched);
}

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cobrar na maquininha e registrar no Mobizweb', () {
    test('aprovado: registra com ATK/NSU, valor da Stone e some dos pendentes', () async {
      final t = await _boot(respond: (_) => _json(200, {'bill': {'total': 40.7, 'paid': 40.7, 'remaining': 0}}), stoneReturn: _approved);
      final outcome = await t.app.ledger.chargeAndRecord(
        kind: 'session',
        targetId: 'sess-1',
        label: 'Mesa 8',
        method: 'credit_card',
        amount: 40.70,
        type: StoneTransactionType.credit,
      );

      expect(outcome.status, ChargeStatus.recorded);
      expect(t.app.ledger.pending, isEmpty);

      // Deeplink: centavos exatos e tipo CREDIT, sem order_id.
      final link = Uri.parse(t.launched.single);
      expect(link.scheme, 'payment-app');
      expect(link.queryParameters['amount'], '4070');
      expect(link.queryParameters['transaction_type'], 'CREDIT');
      expect(link.queryParameters['return_scheme'], 'mobizpos');

      final req = t.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://loja.mobizweb.com.br/api/garcom/v1/sessions/sess-1/payments');
      expect(req.headers['Idempotency-Key'], isNotEmpty);
      expect(req.headers['Accept'], 'application/json');
      final body = jsonDecode(req.body) as Map;
      expect(body['method'], 'credit_card');
      expect(body['amount'], 40.7);
      expect(body['tef_provider'], 'stone_deeplink');
      expect(body['tef_transaction_id'], '37820073187607');
      expect(body['tef_nsu'], '187607');
      expect(body['reference'], 'MASTERCARD ****2166');
    });

    test('comanda usa a rota de pagamento da comanda', () async {
      final t = await _boot(respond: (_) => _json(200, {'comanda': {}}), stoneReturn: _approved);
      await t.app.ledger.chargeAndRecord(
        kind: 'comanda',
        targetId: 'com-9',
        label: 'Comanda 9',
        method: 'debit_card',
        amount: 40.70,
        type: StoneTransactionType.debit,
      );
      expect(t.requests.single.url.path, '/api/garcom/v1/comandas/com-9/payments');
    });

    test('recusado na maquininha: nada é registrado nem fica pendente', () async {
      final t = await _boot(
        respond: (_) => _json(200, {}),
        stoneReturn: 'mobizpos://pay-response?success=false&code=-6&message=N%C3%A3o%20autorizada',
      );
      final outcome = await t.app.ledger.chargeAndRecord(
        kind: 'session',
        targetId: 's',
        label: 'Mesa 1',
        method: 'credit_card',
        amount: 10,
        type: StoneTransactionType.credit,
      );
      expect(outcome.status, ChargeStatus.declined);
      expect(outcome.message, 'Não autorizada');
      expect(t.requests, isEmpty);
      expect(t.app.ledger.pending, isEmpty);
    });

    test('cobrado mas o servidor caiu: fica pendente, gravado no aparelho, e o retry usa a MESMA chave', () async {
      var online = false;
      final t = await _boot(
        respond: (_) => online ? _json(200, {'bill': {}, 'duplicate': true}) : _json(503, {'message': 'fora do ar'}),
        stoneReturn: _approved,
      );
      final outcome = await t.app.ledger.chargeAndRecord(
        kind: 'session',
        targetId: 'sess-1',
        label: 'Mesa 8',
        method: 'credit_card',
        amount: 40.70,
        type: StoneTransactionType.credit,
      );
      expect(outcome.status, ChargeStatus.approvedNotRecorded);
      final pending = t.app.ledger.pending.single;
      expect(pending.isApproved, isTrue);
      expect(pending.atk, '37820073187607');
      // Sobrevive a um fechamento do app.
      expect(t.backend.values['tef_pending'], contains('37820073187607'));

      online = true;
      expect(await t.app.ledger.retry(pending), isNull);
      expect(t.app.ledger.pending, isEmpty);
      expect(t.requests, hasLength(2));
      expect(t.requests[0].headers['Idempotency-Key'], t.requests[1].headers['Idempotency-Key']);
      expect((jsonDecode(t.requests[1].body) as Map)['tef_transaction_id'], '37820073187607');
    });

    test('espera cancelada sem resposta: desfecho desconhecido fica na lista', () async {
      final t = await _boot(respond: (_) => _json(200, {}), stoneReturn: null);
      final outcome = await t.app.ledger.chargeAndRecord(
        kind: 'session',
        targetId: 's',
        label: 'Mesa 1',
        method: 'credit_card',
        amount: 10,
        type: StoneTransactionType.credit,
      );
      expect(outcome.status, ChargeStatus.unknown);
      expect(t.app.ledger.pending.single.state, 'unknown');
      expect(t.requests, isEmpty);
    });

    test('app morto durante a cobrança: a resposta órfã da Stone é conciliada na abertura', () async {
      final backend = MemoryBackend()
        ..values['tef_pending'] = jsonEncode([
          {
            'id': 'x',
            'kind': 'session',
            'target_id': 'sess-7',
            'label': 'Mesa 7',
            'method': 'debit_card',
            'amount': 40.7,
            'idempotency_key': 'key-1',
            'created_at': 0,
            'state': 'inflight',
          },
        ]);
      final t = await _boot(respond: (_) => _json(200, {'bill': {}}), backend: backend, orphan: _approved);
      expect(t.app.ledger.pending, isEmpty);
      final req = t.requests.single;
      expect(req.url.path, '/api/garcom/v1/sessions/sess-7/payments');
      expect(req.headers['Idempotency-Key'], 'key-1');
      expect((jsonDecode(req.body) as Map)['tef_transaction_id'], '37820073187607');
    });

    test('app morto e sem resposta: a cobrança em curso vira "conferir no app da Stone"', () async {
      final backend = MemoryBackend()
        ..values['tef_pending'] = jsonEncode([
          {'id': 'x', 'kind': 'session', 'target_id': 's', 'label': 'Mesa 7', 'method': 'debit_card', 'amount': 5, 'idempotency_key': 'k', 'created_at': 0, 'state': 'inflight'},
        ]);
      final t = await _boot(respond: (_) => _json(200, {}), backend: backend);
      expect(t.app.ledger.pending.single.state, 'unknown');
      expect(t.requests, isEmpty);
    });
  });

  group('formas de pagamento', () {
    test('cartão, Pix e voucher vão para a maquininha; dinheiro e outros não', () {
      expect(terminalTypeFor('credit_card'), StoneTransactionType.credit);
      expect(terminalTypeFor('debit_card'), StoneTransactionType.debit);
      expect(terminalTypeFor('voucher'), StoneTransactionType.voucher);
      expect(terminalTypeFor('pix'), StoneTransactionType.pix);
      expect(terminalTypeFor('cash'), isNull);
      expect(terminalTypeFor('mp_pix'), isNull);
      expect(terminalTypeFor('other'), isNull);
    });

    test('opções do recebimento: Pix online primeiro, sem crediário e sem repetir', () async {
      final t = await _boot(
        respond: (_) => _json(200, {
          'payment_methods': [
            {'id': '1', 'name': 'Dinheiro', 'code': 'especie', 'method': 'cash', 'is_cash': true},
            {'id': '2', 'name': 'Crédito', 'code': 'card_credit', 'method': 'credit_card'},
            {'id': '3', 'name': 'Crédito Elo', 'code': 'elo', 'method': 'credit_card'},
            {'id': '4', 'name': 'Fiado', 'code': 'fiado', 'method': 'credit_account'},
          ],
          'pix_online': {'code': 'mp_pix', 'label': 'Pix MP'},
        }),
      );
      await t.app.methods.load();
      expect(t.app.methods.receiveOptions.map((o) => o.label), ['Pix online', 'Dinheiro', 'Crédito']);
      expect(t.app.methods.receiveOptions[1].isCash, isTrue);
    });

    test('loja sem provedor de Pix online não oferece a opção', () async {
      final t = await _boot(respond: (_) => _json(200, {'payment_methods': <dynamic>[], 'pix_online': null}));
      await t.app.methods.load();
      expect(t.app.methods.receiveOptions.map((o) => o.method), ['cash', 'other']);
    });
  });

  group('cliente da API', () {
    test('401 derruba a sessão local', () async {
      final backend = MemoryBackend()
        ..secure['auth_token'] = 'tok'
        ..values['auth'] = jsonEncode({
          'user': {'id': 'u', 'name': 'Ana', 'email': 'a@a'},
          'store': {'id': 's', 'name': 'Loja'},
          'stores': [
            {'id': 's', 'name': 'Loja'},
          ],
          'permissions': {'open_session': true},
        });
      final t = await _boot(respond: (_) => _json(401, {'message': 'Unauthenticated.'}), backend: backend);
      expect(t.app.auth.isAuthenticated, isTrue);
      expect(t.app.auth.permissions.openSession, isTrue);
      await t.app.tables.fetch();
      await Future<void>.delayed(Duration.zero);
      expect(t.app.auth.isAuthenticated, isFalse);
      expect(backend.secure.containsKey('auth_token'), isFalse);
    });

    test('mensagem do erro: errors.stock > error > errors.* > message', () {
      expect(Api.reasonOf({'error': 'x', 'errors': {'stock': ['Coca: disponível 2']}}), 'Coca: disponível 2');
      expect(Api.reasonOf({'error': 'Mesa fechada.'}), 'Mesa fechada.');
      expect(Api.reasonOf({'message': 'm', 'errors': {'amount': ['Valor inválido']}}), 'Valor inválido');
      expect(Api.reasonOf({'message': 'm'}), 'm');
      expect(Api.reasonOf(const {}), isNull);
    });

    test('login guarda o token no cofre e a loja única entra direto', () async {
      final t = await _boot(
        respond: (req) => _json(200, {
          'token': '1|abc',
          'user': {'id': 'u', 'name': 'Ana', 'email': 'ana@x'},
          'store': null,
          'stores': [
            {'id': 's1', 'name': 'Matriz'},
          ],
          'permissions': {'cash_open': true},
        }),
      );
      expect(await t.app.auth.login('ana@x', 'segredo', deviceName: 'mobiz-pos'), isNull);
      expect(t.app.auth.store!.name, 'Matriz');
      expect(t.backend.secure['auth_token'], '1|abc');
      // O token nunca vai para as preferências comuns.
      expect(t.backend.values.values.any((v) => v.contains('1|abc')), isFalse);
      final body = jsonDecode(t.requests.single.body) as Map;
      expect(body['device_name'], 'mobiz-pos');
      // Login não leva Authorization; as próximas chamadas levam.
      expect(t.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(t.app.api.token, '1|abc');
    });

    test('carrinho reenviado depois de timeout usa a mesma Idempotency-Key', () async {
      var calls = 0;
      final t = await _boot(
        respond: (req) {
          if (req.method == 'POST') {
            calls++;
            return calls == 1 ? _json(503, {}) : _json(201, {'order': {'id': 'o', 'code': '10'}, 'kitchen_sent': true});
          }
          return _json(200, {'session': {'id': 's1', 'status': 'open', 'table': {}}});
        },
      );
      final first = await t.app.session.sendCart('s1', const [], idempotencyKey: 'cart-key');
      expect(first.ok, isFalse);
      expect(first.error, contains('não será duplicado'));
      final second = await t.app.session.sendCart('s1', const [], idempotencyKey: 'cart-key');
      expect(second.ok, isTrue);
      final posts = t.requests.where((r) => r.method == 'POST').toList();
      expect(posts.map((r) => r.headers['Idempotency-Key']).toSet(), {'cart-key'});
    });
  });
}
