import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/main.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _perms = {'open_session': true, 'create_order': true, 'request_bill': true, 'cash_open': true, 'counter_sale': true};

/// Mini-servidor em memória com o essencial do contrato.
http.Response _server(http.Request req) {
  final path = req.url.path.replaceFirst('/api/garcom/v1', '');
  if (path == '/auth/login') {
    final body = jsonDecode(req.body) as Map;
    if (body['password'] != '123456') return _json(401, {'error': 'Credenciais inválidas.'});
    return _json(200, {
      'token': '1|tok',
      'user': {'id': 'u', 'name': 'Ana', 'email': body['email']},
      'store': {'id': 's1', 'name': 'Bar do Zé'},
      'stores': [
        {'id': 's1', 'name': 'Bar do Zé'},
      ],
      'permissions': _perms,
    });
  }
  if (req.headers['Authorization'] != 'Bearer 1|tok') return _json(401, {'message': 'Unauthenticated.'});
  switch (path) {
    case '/auth/me':
      return _json(200, {'permissions': _perms});
    case '/tables':
      return _json(200, {
        'settings': {'enable_comandas': true, 'idle_alert_minutes': 0},
        'tables': [
          {'id': 't1', 'number': '1', 'label': 'Mesa 1', 'status': 'available', 'area': {'id': 'a', 'name': 'Salão'}},
          {
            'id': 't2',
            'number': '2',
            'label': 'Mesa 2',
            'status': 'occupied',
            'session': {'id': 'sess2', 'status': 'open', 'opened_at': '2026-11-13T12:00:00Z', 'guest_count': 3, 'total': 57.9},
          },
          {'id': 't10', 'number': '10', 'label': 'Mesa 10', 'status': 'closing', 'session': {'id': 'sess10', 'status': 'closing', 'opened_at': '2026-11-13T12:00:00Z', 'total': 10}},
        ],
      });
    case '/menu':
      return _json(200, {'categories': <dynamic>[]});
    case '/payment-methods':
      return _json(200, {'payment_methods': <dynamic>[], 'pix_online': null});
  }
  return _json(404, {'message': 'not found'});
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 740));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(
    () => App.boot(
      backend: MemoryBackend()..values['server_input'] = 'bardoze',
      client: MockClient((req) async => _server(req)),
      probeDevice: false,
    ),
  );
  await tester.pumpWidget(const MobizApp());
  await tester.pump();
}

/// Deixa as chamadas HTTP falsas terminarem e redesenha.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Tira a árvore da tela para os timers de polling serem cancelados.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  testWidgets('abre no login, mostra a loja configurada e recusa senha errada', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Entrar'), findsWidgets);
    expect(find.text('bardoze.mobizweb.com.br'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'ana@x.com');
    await tester.enterText(find.byType(TextField).at(1), 'errada');
    await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
    await _settle(tester);

    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    expect(app.auth.isAuthenticated, isFalse);
    await _unmount(tester);
  });

  testWidgets('login leva ao mapa de mesas, com status, total e ordem natural', (tester) async {
    await _pumpApp(tester);
    await tester.enterText(find.byType(TextField).at(0), 'ana@x.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
    await _settle(tester);

    expect(app.auth.isAuthenticated, isTrue);
    expect(find.text('Mesas'), findsOneWidget);
    expect(find.text('Bar do Zé'), findsOneWidget);
    expect(find.text('Mesa 1'), findsOneWidget);
    expect(find.text('Livre'), findsOneWidget);
    expect(find.text('Ocupada'), findsOneWidget);
    expect(find.text('Fechando'), findsWidgets);
    expect(find.text('3 pessoa(s)'), findsOneWidget);
    expect(find.text('R\$ 57,90'), findsOneWidget);

    // Mesa 2 vem antes da Mesa 10 (ordem numérica, não alfabética).
    final y2 = tester.getTopLeft(find.text('Mesa 2')).dy;
    final y10 = tester.getTopLeft(find.text('Mesa 10')).dy;
    expect(y2, lessThanOrEqualTo(y10));
    expect(tester.takeException(), isNull);

    // Filtro "Livres" deixa só a mesa disponível.
    await tester.tap(find.text('Livres'));
    await tester.pump();
    expect(find.text('Mesa 1'), findsOneWidget);
    expect(find.text('Mesa 2'), findsNothing);

    // Sessão revogada no servidor (401) devolve o app ao login.
    await tester.runAsync(app.auth.clearLocal);
    await tester.pump();
    expect(find.text('Mesas'), findsNothing);
    expect(find.text('Entrar'), findsWidgets);
    await _unmount(tester);
  });
}
