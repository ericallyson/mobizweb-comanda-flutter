import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/stores/comanda_link.dart';
import 'package:mobizweb_pos/stores/notifications.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _inbox({bool withCalls = true}) => {
  'calls': withCalls
      ? [
          {
            'id': 'c1',
            'table_id': 't3',
            'table_number': '3',
            'table_label': 'Mesa 3',
            'table_session_id': 's3',
            'reason': 'waiter',
            'reason_label': 'Chamar garçom',
            'status': 'open',
            'note': null,
            'created_at': '2026-11-14T15:00:00Z',
            'elapsed_seconds': 120,
          },
          {
            'id': 'c2',
            'table_id': 't3',
            'table_label': 'Mesa 3',
            'reason_label': 'Pedir a conta',
            'status': 'acknowledged',
            'note': 'Com CPF',
            'elapsed_seconds': 400,
          },
        ]
      : <dynamic>[],
  'pending_orders': [
    {
      'id': 'o1',
      'table_id': 't2',
      'table_number': 2,
      'table_label': 'Mesa 2',
      'items': [
        {'name': 'Água mineral', 'quantity': 2},
        {'name': 'Pudim', 'quantity': '1.0000'},
      ],
      'elapsed_seconds': 30,
    },
  ],
  'pending_by_table': {'t3': 2},
  'low_stock_alerts': [
    {'id': 'i1', 'name': 'Bacon fatiado', 'unit': 'kg', 'current_stock': -300, 'min_stock': 1, 'kind': 'ingredient'},
    {
      'id': 'p1',
      'name': 'Pão brioche',
      'unit': 'un',
      'current_stock': '0.0000',
      'min_stock': '20.0000',
      'kind': 'product',
    },
  ],
};

Future<({App app, List<http.Request> requests})> _boot(http.Response Function(http.Request) respond) async {
  final requests = <http.Request>[];
  final app = await App.boot(
    backend: MemoryBackend()..values['server_input'] = 'loja',
    client: MockClient((req) async {
      requests.add(req);
      return respond(req);
    }),
    probeDevice: false,
  );
  return (app: app, requests: requests);
}

String _path(http.Request r) => r.url.path.replaceFirst('/api/garcom/v1', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('notificações (sino)', () {
    test('carrega chamados, pedidos do tablet e estoque crítico de GET /tablet/calls', () async {
      final t = await _boot((_) => _json(200, _inbox()));
      final n = t.app.notifications;
      var notified = 0;
      n.addListener(() => notified++);
      expect(n.loaded, isFalse);

      await n.fetch();

      expect(t.requests.single.method, 'GET');
      expect(_path(t.requests.single), '/tablet/calls');
      expect(n.loaded, isTrue);
      expect(notified, greaterThan(0));
      expect(n.calls.map((c) => c.id), ['c1', 'c2']);
      expect(n.calls.first.tableLabel, 'Mesa 3');
      expect(n.calls.first.reasonLabel, 'Chamar garçom');
      expect(n.calls.first.isAcknowledged, isFalse);
      expect(n.calls.last.isAcknowledged, isTrue);
      expect(n.calls.last.note, 'Com CPF');
      expect(n.pendingOrders.single.tableLabel, 'Mesa 2');
      expect(n.pendingOrders.single.items.map((i) => '${i.quantity} ${i.name}'), ['2.0 Água mineral', '1.0 Pudim']);
      expect(n.pendingFor('t3'), 2);
      expect(n.pendingFor('outra'), 0);
      expect(n.lowStockAlerts.map((a) => a.name), ['Bacon fatiado', 'Pão brioche']);
      expect(n.lowStockAlerts.first.currentStock, -300);
      expect(n.lowStockAlerts.last.minStock, 20);
    });

    test('o número do sino conta chamados e pedidos, mas NÃO o estoque crítico', () async {
      final t = await _boot((_) => _json(200, _inbox()));
      await t.app.notifications.fetch();
      expect(t.app.notifications.count, 3);

      final u = await _boot((_) => _json(200, {..._inbox(withCalls: false), 'pending_orders': <dynamic>[]}));
      await u.app.notifications.fetch();
      expect(u.app.notifications.count, 0);
      expect(u.app.notifications.lowStockAlerts, hasLength(2));
      expect(u.app.notifications.isEmpty, isFalse);
    });

    test('servidor antigo sem low_stock_alerts não quebra', () async {
      final t = await _boot((_) => _json(200, {'calls': <dynamic>[], 'pending_orders': <dynamic>[]}));
      await t.app.notifications.fetch();
      expect(t.app.notifications.lowStockAlerts, isEmpty);
      expect(t.app.notifications.isEmpty, isTrue);
      expect(t.app.notifications.loaded, isTrue);
    });

    test('"Estou indo" marca a caminho e chama /ack com Idempotency-Key', () async {
      final t = await _boot((req) => req.method == 'GET' ? _json(200, _inbox()) : _json(200, {'ok': true}));
      final n = t.app.notifications;
      await n.fetch();

      expect(await n.acknowledge('c1'), isNull);

      expect(n.calls.first.isAcknowledged, isTrue);
      expect(n.count, 3);
      final post = t.requests.last;
      expect(post.method, 'POST');
      expect(_path(post), '/tablet/calls/c1/ack');
      expect(post.headers['Idempotency-Key'], isNotEmpty);
    });

    test('"Atendida" tira da lista, baixa o sino e a pendência da mesa', () async {
      final t = await _boot((req) => req.method == 'GET' ? _json(200, _inbox()) : _json(200, {'ok': true}));
      final n = t.app.notifications;
      await n.fetch();

      expect(await n.resolve('c1'), isNull);

      expect(n.calls.map((c) => c.id), ['c2']);
      expect(n.count, 2);
      expect(n.pendingFor('t3'), 1);
      expect(_path(t.requests.last), '/tablet/calls/c1/resolve');
    });

    test('"Liberar" pedido do tablet chama /tablet/orders/{id}/approve', () async {
      final t = await _boot((req) => req.method == 'GET' ? _json(200, _inbox()) : _json(200, {'ok': true}));
      final n = t.app.notifications;
      await n.fetch();

      expect(await n.approveOrder('o1'), isNull);

      expect(n.pendingOrders, isEmpty);
      expect(_path(t.requests.last), '/tablet/orders/o1/approve');
    });

    test('recusa do servidor devolve a mensagem e recarrega a lista (desfaz o otimismo)', () async {
      final t = await _boot(
        (req) =>
            req.method == 'GET' ? _json(200, _inbox()) : _json(403, {'message': 'Sem permissão para liberar pedidos.'}),
      );
      final n = t.app.notifications;
      await n.fetch();

      final error = await n.approveOrder('o1');

      expect(error, 'Sem permissão para liberar pedidos.');
      expect(n.pendingOrders.single.id, 'o1');
      expect(t.requests.map((r) => r.method), ['GET', 'POST', 'GET']);
    });

    test('sem rede mantém o que já estava na tela', () async {
      var online = true;
      final t = await _boot((_) => online ? _json(200, _inbox()) : throw http.ClientException('offline'));
      final n = t.app.notifications;
      await n.fetch();
      online = false;
      await n.fetch();
      expect(n.calls, hasLength(2));
      expect(n.loading, isFalse);
    });

    test('trocar de loja ou sair limpa as notificações', () async {
      final t = await _boot((_) => _json(200, _inbox()));
      await t.app.notifications.fetch();
      t.app.resetDomain();
      expect(t.app.notifications.count, 0);
      expect(t.app.notifications.lowStockAlerts, isEmpty);
      expect(t.app.notifications.loaded, isFalse);
    });

    test('tempo decorrido soma o relógio do aparelho ao que o servidor informou', () {
      final at = DateTime(2026, 11, 14, 12);
      expect(elapsedLabel(40, at, at), 'há 40s');
      expect(elapsedLabel(40, at, at.add(const Duration(seconds: 30))), 'há 1 min');
      expect(elapsedLabel(3600, at, at.add(const Duration(minutes: 5))), 'há 1h05');
      expect(elapsedLabel(10, at, at.subtract(const Duration(minutes: 1))), 'há 0s');
      expect(isLateCall(200, at, at.add(const Duration(seconds: 99))), isFalse);
      expect(isLateCall(200, at, at.add(const Duration(seconds: 100))), isTrue);
    });
  });

  group('ler QR da comanda (código digitado)', () {
    test('lookup envia o código e diz se a comanda já está em uma mesa', () async {
      final t = await _boot(
        (req) => _json(200, {
          'comanda_table': {'id': 'ct', 'number': '101', 'label': '101'},
          'linked': true,
          'link': {'table_number': 7},
        }),
      );
      final found = await t.app.comandaLink.lookup(' 101 ');
      expect(_path(t.requests.single), '/tablet/comandas/lookup');
      expect(jsonDecode(t.requests.single.body), {'code': '101'});
      expect(found.label, '101');
      expect(found.linked, isTrue);
      expect(found.tableNumber, '7');
    });

    test('comanda inexistente mostra a mensagem do servidor', () async {
      final t = await _boot((_) => _json(404, {'message': 'Comanda não encontrada nesta loja.'}));
      expect(
        () => t.app.comandaLink.lookup('999'),
        throwsA(isA<ComandaLinkException>().having((e) => e.message, 'message', 'Comanda não encontrada nesta loja.')),
      );
    });

    test('link envia código e mesa e devolve o número da mesa', () async {
      final t = await _boot(
        (_) => _json(201, {
          'link': {'table_number': '12', 'table_id': 't12'},
        }),
      );
      expect(await t.app.comandaLink.link('101', 't12'), '12');
      expect(_path(t.requests.single), '/tablet/comandas/link');
      expect(jsonDecode(t.requests.single.body), {'code': '101', 'table_id': 't12'});
      expect(t.requests.single.headers['Idempotency-Key'], isNotEmpty);
    });

    test('comanda já vinculada a outra mesa (409) mostra o motivo, não a mensagem genérica', () async {
      final t = await _boot(
        (_) => _json(409, {'message': 'Esta comanda já está vinculada à mesa 3. Feche-a antes de vincular a outra.'}),
      );
      expect(
        () => t.app.comandaLink.link('101', 't12'),
        throwsA(
          isA<ComandaLinkException>().having(
            (e) => e.message,
            'message',
            startsWith('Esta comanda já está vinculada à mesa 3'),
          ),
        ),
      );
    });
  });
}
