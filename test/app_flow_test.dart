import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/main.dart';
import 'package:mobizweb_pos/ui/kit.dart';
import 'package:mobizweb_pos/ui/screens/cash_screen.dart';
import 'package:mobizweb_pos/ui/screens/menu_screen.dart';
import 'package:mobizweb_pos/ui/screens/more_screen.dart';
import 'package:mobizweb_pos/ui/screens/notifications_screen.dart';
import 'package:mobizweb_pos/ui/screens/session_screen.dart';
import 'package:mobizweb_pos/ui/table_card.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _perms = {
  'open_session': true,
  'create_order': true,
  'request_bill': true,
  'cash_open': true,
  'counter_sale': true,
};

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
        {'id': 's2', 'name': 'Bar da Praia'},
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
          {
            'id': 't1',
            'number': '1',
            'label': 'Mesa 1',
            'status': 'available',
            'area': {'id': 'a', 'name': 'Salão'},
          },
          {
            'id': 't2',
            'number': '2',
            'label': 'Mesa 2',
            'status': 'occupied',
            'pending_calls': 1,
            'session': {
              'id': 'sess2',
              'status': 'open',
              'opened_at': '2026-11-13T12:00:00Z',
              'guest_count': 3,
              'opened_by_name': 'Wanderson',
              'total': 57.9,
            },
          },
          {
            'id': 't10',
            'number': '10',
            'label': 'Mesa 10',
            'status': 'closing',
            'session': {'id': 'sess10', 'status': 'closing', 'opened_at': '2026-11-13T12:00:00Z', 'total': 10},
          },
        ],
      });
    case '/tablet/calls':
      return _json(200, {
        'calls': [
          {
            'id': 'c1',
            'table_id': 't2',
            'table_label': 'Mesa 2',
            'reason_label': 'Chamar garçom',
            'status': 'open',
            'elapsed_seconds': 65,
          },
        ],
        'pending_orders': <dynamic>[],
        'pending_by_table': {'t2': 1},
        'low_stock_alerts': [
          {
            'id': 'i1',
            'name': 'Bacon fatiado',
            'unit': 'kg',
            'current_stock': -300,
            'min_stock': 1,
            'kind': 'ingredient',
          },
        ],
      });
    case '/cash':
      return _json(200, {
        'enabled': true,
        'settings': {'blind_close': false},
        'permissions': {'open': true, 'close': true, 'movement': true, 'financial': true},
        'session': null,
      });
    case '/menu':
      return _json(200, {'categories': <dynamic>[]});
    case '/payment-methods':
      return _json(200, {'payment_methods': <dynamic>[], 'pix_online': null});
  }
  return _json(404, {'message': 'not found'});
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
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

Future<void> _login(WidgetTester tester) async {
  await _pumpApp(tester);
  await tester.enterText(find.byType(TextField).at(0), 'ana@x.com');
  await tester.enterText(find.byType(TextField).at(1), '123456');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await _settle(tester);
}

/// Card da mesa de número [number] no mapa.
Finder _card(String number) => find.byWidgetPredicate((w) => w is TableCard && w.table.number == number);

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

  testWidgets('login leva ao mapa de mesas no layout novo, com menu inferior, chips e ordem natural', (tester) async {
    final semantics = tester.ensureSemantics();
    await _login(tester);

    expect(app.auth.isAuthenticated, isTrue);
    // Topo: loja com troca, garçom e só o sino.
    expect(find.text('Bar do Zé'), findsOneWidget);
    expect(find.text('Garçom Ana'), findsOneWidget);
    expect(find.byType(HeaderButton), findsOneWidget);
    expect(find.bySemanticsLabel('Notificações (1)'), findsOneWidget);
    // Menu inferior com as 4 abas com nome.
    for (final tab in ['Mesas', 'Balcão', 'Caixa', 'Mais']) {
      expect(find.descendant(of: find.byType(MainTabBar), matching: find.text(tab)), findsOneWidget);
    }
    // Chips com contagem.
    expect(find.text('Todas 3'), findsOneWidget);
    expect(find.text('Livres 1'), findsOneWidget);
    expect(find.text('Ocupadas 1'), findsOneWidget);
    expect(find.text('Fechando 1'), findsOneWidget);
    expect(find.text('Ociosas 0'), findsOneWidget);
    expect(find.text('Pendentes 1'), findsOneWidget);
    expect(find.textContaining('Reservas'), findsNothing);
    // Cards: status lido pela cor; o texto fica no rótulo de acessibilidade.
    expect(find.byType(TableCard), findsNWidgets(3));
    expect(find.text('livre'), findsOneWidget);
    expect(find.text('Wanderson'), findsOneWidget);
    expect(find.text('R\$57,90'), findsOneWidget);
    expect(find.bySemanticsLabel('Mesa 1, livre'), findsOneWidget);
    expect(find.bySemanticsLabel('Mesa 2, ocupada, Wanderson, R\$ 57,90, chamado pendente'), findsOneWidget);
    expect(find.bySemanticsLabel('Mesa 10, fechando, R\$ 10,00'), findsOneWidget);

    // Mesa 2 vem antes da Mesa 10 (ordem numérica, não alfabética).
    final p2 = tester.getTopLeft(_card('2'));
    final p10 = tester.getTopLeft(_card('10'));
    expect(p2.dy < p10.dy || (p2.dy == p10.dy && p2.dx < p10.dx), isTrue);
    expect(tester.takeException(), isNull);

    // A faixa de chips rola de lado até o último chip aparecer inteiro; a página não rola de lado.
    await tester.drag(find.text('Ocupadas 1'), const Offset(-600, 0));
    await tester.pump();
    expect(tester.getRect(find.text('Pendentes 1')).right, lessThanOrEqualTo(390 - 14));
    expect(tester.getRect(find.byType(TableCard).first).left, 14);
    await tester.drag(find.text('Pendentes 1'), const Offset(600, 0));
    await tester.pump();

    // Filtro "Livres" deixa só a mesa disponível.
    await tester.tap(find.text('Livres 1'));
    await tester.pump();
    expect(_card('1'), findsOneWidget);
    expect(_card('2'), findsNothing);

    // Sessão revogada no servidor (401) devolve o app ao login.
    await tester.runAsync(app.auth.clearLocal);
    await tester.pump();
    expect(find.byType(MainTabBar), findsNothing);
    expect(find.text('Entrar'), findsWidgets);
    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('buscar e Entrar: filtra enquanto digita, abre a mesa digitada e avisa quando não existe', (
    tester,
  ) async {
    await _login(tester);
    final field = find.byType(TextField);

    // Enquanto digita, a grade filtra (como antes).
    await tester.enterText(field, '1');
    await tester.pump();
    expect(_card('1'), findsOneWidget);
    expect(_card('10'), findsOneWidget);
    expect(_card('2'), findsNothing);

    // Mesa inexistente: só o aviso.
    await tester.enterText(field, '99');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Mesa 99 não existe neste salão'), findsOneWidget);
    expect(find.byType(SessionScreen), findsNothing);

    // Mesa livre: vai direto ao cardápio, sem formulário "Abrir mesa".
    await tester.enterText(field, '1');
    await tester.tap(find.text('Entrar'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TableMenuScreen), findsOneWidget);
    expect(find.text('Abrir Mesa 1'), findsNothing);
    expect(find.text('Nova mesa · Ana'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(TableMenuScreen), findsNothing);

    // Mesa ocupada: "2" + Entrar abre a mesa 2 (e não a 10 ou outra parecida).
    await tester.enterText(field, '2');
    await tester.tap(find.text('Entrar'));
    await _settle(tester);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(tester.widget<SessionScreen>(find.byType(SessionScreen)).sessionId, 'sess2');
    await _unmount(tester);
  });

  testWidgets('menu inferior: Caixa e Mais mantêm o menu; Mais lista as funções na ordem e abre Notificações', (
    tester,
  ) async {
    await _login(tester);

    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Caixa')));
    await _settle(tester);
    expect(find.byType(CashScreen), findsOneWidget);
    expect(find.byType(MainTabBar), findsOneWidget);
    expect(find.text('Atualizar'), findsOneWidget);
    expect(find.text('Informe o valor inicial (fundo de troco).'), findsOneWidget);
    expect(find.text('Abrir caixa'), findsNWidgets(2));

    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Mais')));
    await _settle(tester);
    expect(find.byType(MoreScreen), findsOneWidget);
    expect(find.byType(MainTabBar), findsOneWidget);
    expect(find.text('Garçom Ana · Bar do Zé'), findsOneWidget);
    final rows = ['Notificações', 'Ler QR da comanda', 'Atualizar', 'Trocar loja', 'Configurações', 'Sair'];
    final ys = [for (final r in rows) tester.getTopLeft(find.text(r)).dy];
    expect(ys, [...ys]..sort());

    // Notificações abre por cima e "voltar" retorna para Mais.
    await tester.tap(find.text('Notificações'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Chamar garçom'), findsOneWidget);
    expect(find.text('Estou indo'), findsOneWidget);
    expect(find.text('Atendida'), findsOneWidget);
    expect(find.text('ESTOQUE CRÍTICO'), findsOneWidget);
    expect(find.text('Bacon fatiado'), findsOneWidget);
    expect(find.text('-300 kg'), findsOneWidget);
    expect(find.text('mínimo 1 kg'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.byType(MoreScreen), findsOneWidget);

    // Sair continua existindo, com a confirmação.
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Sair do app?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.auth.isAuthenticated, isTrue);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
