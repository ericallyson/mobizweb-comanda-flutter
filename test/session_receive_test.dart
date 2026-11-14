// Mesa aberta (5.5), Receber conta / Receber venda (5.6) e balcão (5.7) do
// layout novo, mais o QR do tablet e a leitura do QR da comanda pela câmera.
// O que estes testes guardam: as 9 opções de hoje continuam na tela e nenhuma
// é nova; o pagamento parcial fica na tela com o novo restante e o total
// fecha a mesa; cartão continua passando pelo TefLedger com os campos de TEF;
// dinheiro exige o valor recebido; balcão divide em duas formas.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/main.dart';
import 'package:mobizweb_pos/stores/comanda_link.dart';
import 'package:mobizweb_pos/stores/receive.dart';
import 'package:mobizweb_pos/ui/kit.dart';
import 'package:mobizweb_pos/ui/screens/counter_screen.dart';
import 'package:mobizweb_pos/ui/screens/menu_screen.dart';
import 'package:mobizweb_pos/ui/screens/receive_screen.dart';
import 'package:mobizweb_pos/ui/screens/session_screen.dart';
import 'package:mobizweb_pos/ui/sheets/comanda_link_sheet.dart';
import 'package:mobizweb_pos/ui/sheets/items_sheet.dart';
import 'package:mobizweb_pos/ui/sheets/session_sheets.dart';
import 'package:mobizweb_pos/ui/sheets/tablet_code_sheet.dart';
import 'package:mobizweb_pos/ui/table_card.dart';

const _channel = MethodChannel('mobiz/native');

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _allPerms = {
  'open_session': true,
  'create_order': true,
  'send_order': true,
  'request_bill': true,
  'process_payment': true,
  'close_session': true,
  'reopen_session': true,
  'cancel_session': true,
  'cancel_item': true,
  'transfer_item': true,
  'transfer_table': true,
  'manage_comanda': true,
  'couvert_add': true,
  'couvert_remove': true,
  'counter_sale': true,
};

/// PNG 1x1 válido (o "QR" que o lado nativo devolveria).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

typedef _Call = ({String method, String path, Map<String, dynamic> body, Map<String, String> headers});

/// Mini-servidor em memória com a mesa 2 aberta: 2 long necks e 1 x-burger
/// (R$ 44,00 + 10% = R$ 48,40). Guarda as chamadas e fecha a mesa ao quitar.
class _Server {
  _Server({this.perms = _allPerms, this.comandas = false});
  final Map<String, bool> perms;

  /// Mesa 2 com as comandas "Ana" e "Bia".
  final bool comandas;
  final calls = <_Call>[];
  final payments = <Map<String, dynamic>>[];
  String status = 'open';
  bool closesWhenPaid = true;
  final canceled = <String>{};

  static const _items = [
    {'id': 'i1', 'product_name': 'Long neck', 'quantity': 2, 'unit_price': 11.0, 'notes': null},
    {'id': 'i2', 'product_name': 'X-Burger', 'quantity': 1, 'unit_price': 22.0, 'notes': 'sem cebola'},
  ];

  Iterable<_Call> get mutations => calls.where((c) => c.method != 'GET' && c.path != '/auth/login');
  List<String> get mutationPaths => [for (final c in mutations) '${c.method} ${c.path}'];

  double get _subtotal => _items
      .where((i) => !canceled.contains(i['id']))
      .fold(0, (a, i) => a + (i['unit_price']! as double) * (i['quantity']! as int));
  double get _total => (_subtotal * 110).round() / 100;
  double get _paid => payments.fold(0, (a, p) => a + (p['amount'] as num).toDouble());
  double get _remaining => ((_total - _paid) * 100).round() / 100;

  Map<String, dynamic> get _bill => {
    'items_subtotal': _subtotal,
    'service_fee': _total - _subtotal,
    'service_fee_percentage': 10,
    'total': _total,
    'paid': _paid,
    'remaining': _remaining < 0 ? 0 : _remaining,
  };

  Map<String, dynamic> get _session => {
    'id': 'sess2',
    'status': status,
    'guest_count': 3,
    'customer_name': 'Jefferson',
    'table': {'id': 't2', 'number': '2', 'label': 'Mesa 2'},
    'has_comandas': comandas,
    'enable_comandas': true,
    'comandas': [
      if (comandas) ...[
        {'id': 'cmd-a', 'label': 'Ana', 'status': 'open'},
        {'id': 'cmd-b', 'label': 'Bia', 'status': 'open'},
      ],
    ],
    'items': [
      for (final i in _items)
        {
          ...i,
          'status': canceled.contains(i['id']) ? 'canceled' : 'pending',
          'can_cancel': true,
          'can_transfer': true,
          'comanda_id': comandas ? (i['id'] == 'i1' ? 'cmd-a' : 'cmd-b') : null,
        },
    ],
    'free_tables': [
      {'id': 't1', 'number': '1'},
    ],
    'transfer_targets': <dynamic>[],
    'bill': _bill,
  };

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/api/garcom/v1', '');
    final body = req.body.isEmpty ? <String, dynamic>{} : (jsonDecode(req.body) as Map).cast<String, dynamic>();
    calls.add((method: req.method, path: path, body: body, headers: req.headers));
    final live = status == 'open' || status == 'closing';

    switch (path) {
      case '/auth/login':
        return _json(200, {
          'token': '1|tok',
          'user': {'id': 'u', 'name': 'Ana', 'email': body['email']},
          'store': {'id': 's1', 'name': 'Bar do Zé'},
          'stores': [
            {'id': 's1', 'name': 'Bar do Zé'},
          ],
          'permissions': perms,
        });
      case '/auth/me':
        return _json(200, {'permissions': perms});
      case '/tables':
        return _json(200, {
          'settings': {'enable_comandas': true, 'idle_alert_minutes': 0},
          'tables': [
            {'id': 't1', 'number': '1', 'label': 'Mesa 1', 'status': 'available'},
            {
              'id': 't2',
              'number': '2',
              'label': 'Mesa 2',
              'status': !live ? 'available' : (status == 'closing' ? 'closing' : 'occupied'),
              if (live)
                'session': {
                  'id': 'sess2',
                  'status': status,
                  'opened_at': '2026-11-14T12:00:00Z',
                  'guest_count': 3,
                  'customer_name': 'Jefferson',
                  'opened_by_name': 'Wanderson',
                  'total': _total,
                },
            },
          ],
        });
      case '/tablet/calls':
        return _json(200, {'calls': <dynamic>[], 'pending_orders': <dynamic>[], 'low_stock_alerts': <dynamic>[]});
      case '/menu':
        return _json(200, {
          'categories': [
            {
              'id': 'c1',
              'name': 'Bebidas',
              'parent_id': null,
              'products': [
                {
                  'id': 'guarana',
                  'name': 'Guaraná Lata',
                  'type': 'simple',
                  'price': 7,
                  'is_available': true,
                  'unit_of_measure': 'un',
                  'allow_fractional_qty': false,
                  'addon_groups': <dynamic>[],
                },
              ],
            },
          ],
        });
      case '/payment-methods':
        return _json(200, {
          'payment_methods': [
            {'code': 'especie', 'name': 'Dinheiro', 'method': 'cash', 'is_default': true, 'is_cash': true},
            {'code': 'card_credit', 'name': 'Crédito', 'method': 'credit_card'},
            {'code': 'card_debit', 'name': 'Débito', 'method': 'debit_card'},
            {'code': 'pix', 'name': 'Pix', 'method': 'pix'},
          ],
          'pix_online': null,
        });
      case '/counter/context':
        return _json(200, {
          'enabled': true,
          'permissions': {'sell': true},
          'payment_methods': [
            {'code': 'especie', 'name': 'Dinheiro', 'method': 'cash', 'is_default': true, 'is_cash': true},
            {'code': 'card_debit', 'name': 'Débito', 'method': 'debit_card'},
            {'code': 'card_credit', 'name': 'Crédito', 'method': 'credit_card'},
          ],
          'cash_session': null,
        });
      case '/counter/checkout':
        return _json(201, {
          'order': {'id': 'o1', 'number': 101, 'total': 14, 'change_amount': 0},
          'receipt': {'status': 'skipped', 'requires_operator_decision': false},
        });
      case '/tablet/comandas/lookup':
        return body['code'] == '101'
            ? _json(200, {
                'comanda_table': {'id': 'c101', 'label': '101'},
                'linked': false,
                'link': null,
              })
            : _json(404, {'message': 'Comanda não encontrada nesta loja.'});
      case '/sessions/sess2':
        return _json(200, {'session': _session});
      case '/sessions/sess2/receipt':
        return _json(200, {
          'receipt': {
            'payments': [
              for (final p in payments) {'label': p['label'], 'amount': p['amount'], 'change': 0},
            ],
          },
        });
      case '/sessions/sess2/payments':
        final amount = (body['amount'] as num).toDouble();
        if (body['method'] == 'cash' && ((body['cash_received'] as num?) ?? 0) < amount) {
          return _json(422, {'error': 'Valor recebido é menor que o valor do pagamento.'});
        }
        const labels = {'cash': 'Dinheiro', 'pix': 'Pix', 'credit_card': 'Crédito', 'debit_card': 'Débito'};
        payments.add({'label': labels[body['method']] ?? body['method'], 'amount': amount});
        if (_remaining <= 0.005 && closesWhenPaid) status = 'closed';
        return _json(200, {'bill': _bill});
      case '/sessions/sess2/close':
        status = 'closed';
        return _json(200, {'closed': true});
      case '/sessions/sess2/reopen':
        status = 'open';
        return _json(200, {'message': 'Mesa reaberta.'});
      case '/sessions/sess2/tablet-code':
        return _json(200, {'code': '482913', 'table_number': '2'});
      case '/sessions/sess2/comandas':
        return _json(200, {
          'comandas': [
            {
              'id': 'cmd-a',
              'label': 'Ana',
              'status': 'open',
              'items_subtotal': 22,
              'service_fee': 2.2,
              'service_fee_percentage': 10,
              'total': 24.2,
              'paid': 0,
              'remaining': 24.2,
              'items_count': 1,
            },
          ],
          'available': <dynamic>[],
          'transfer_tables': <dynamic>[],
        });
      case '/tables/t2/sessions/current/bill':
        status = 'closing';
        return _json(200, {'message': 'Conta solicitada.'});
      case '/items/i1':
        canceled.add('i1');
        return _json(200, {'message': 'Item cancelado.'});
    }
    return _json(404, {'message': 'not found'});
  }
}

/// O que a maquininha falsa (canal nativo) recebeu e devolve.
class _Device {
  final launched = <String>[];
  final scanPrompts = <String?>[];

  /// Deeplink de retorno do pagamento (`null` = ninguém atende).
  String? stoneReturn;

  /// O que a câmera "leu"; [scanError] simula `no_camera` / `denied`.
  String? scan;
  String? scanError;

  /// `true` = o lado nativo desenha o QR do tablet.
  bool drawsQr = false;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'launch':
        launched.add((call.arguments as Map)['uri'] as String);
        if (stoneReturn == null) throw PlatformException(code: 'abandoned');
        return stoneReturn;
      case 'scanQr':
        scanPrompts.add((call.arguments as Map)['prompt'] as String?);
        if (scanError != null) throw PlatformException(code: scanError!, message: 'erro');
        return scan;
      case 'qrPng':
        if (!drawsQr) throw MissingPluginException();
        return _png;
      default:
        return null;
    }
  }
}

Future<_Device> _boot(WidgetTester tester, _Server server, {bool stone = false}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final device = _Device();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, device.handle);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  await tester.runAsync(
    () => App.boot(
      backend: MemoryBackend()..values['server_input'] = 'bardoze',
      client: MockClient(server.handle),
      probeDevice: false,
    ),
  );
  if (stone) app.terminal.stoneAvailable = true;
  return device;
}

/// Deixa as chamadas HTTP falsas terminarem e redesenha.
Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Device> _login(WidgetTester tester, _Server server, {bool stone = false}) async {
  final device = await _boot(tester, server, stone: stone);
  await tester.pumpWidget(const MobizApp());
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(0), 'ana@x.com');
  await tester.enterText(find.byType(TextField).at(1), '123456');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await _settle(tester);
  return device;
}

/// Tira a árvore da tela para os timers de polling serem cancelados.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Finder _tableCard(String number) => find.byWidgetPredicate((w) => w is TableCard && w.table.number == number);

Future<void> _openTable2(WidgetTester tester) async {
  await tester.tap(_tableCard('2'));
  await _settle(tester);
  await tester.pumpAndSettle();
  expect(find.byType(SessionScreen), findsOneWidget);
}

Future<void> _openReceive(WidgetTester tester) async {
  await _openTable2(tester);
  await tester.tap(find.widgetWithText(Btn, 'Receber conta'));
  await _settle(tester);
  await tester.pumpAndSettle();
  expect(find.byType(ReceiveScreen), findsOneWidget);
}

/// O campo ao lado do rótulo ("Valor", "Valor recebido", "Cliente (opcional)").
Finder _field(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ValueRow'),
  ),
  matching: find.byType(TextField),
);

/// O botão único da barra inferior da tela de recebimento.
Btn _barButton(WidgetTester tester) =>
    tester.widget<Btn>(find.descendant(of: find.byType(BottomBar), matching: find.byType(Btn)));

Future<void> _tapBar(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(BottomBar), matching: find.byType(Btn)));
  await _settle(tester);
  await tester.pump(const Duration(seconds: 3));
}

/// Espera o aviso (toast) sair de cena, para o próximo poder aparecer.
Future<void> _toastGone(WidgetTester tester) async {
  // Entra, conta o tempo de exibição e sai: cada etapa precisa do seu quadro.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

const _gridOptions = [
  'Gerar QR do tablet na mesa',
  'Ver conta parcial',
  'Lançar couvert',
  'Comandas da mesa',
  'Transferir mesa',
  'Transferir item',
];

void main() {
  test('QR da comanda: o código enviado é o conteúdo lido, sem os espaços das pontas', () {
    expect(comandaCodeFromQr('101'), '101');
    expect(comandaCodeFromQr('  101\n'), '101');
    // O PWA manda o conteúdo inteiro: quem interpreta é o servidor.
    expect(comandaCodeFromQr(' https://loja.mobizweb.com.br/c/ABC-101 '), 'https://loja.mobizweb.com.br/c/ABC-101');
    expect(comandaCodeFromQr(''), isNull);
    expect(comandaCodeFromQr('   '), isNull);
    expect(comandaCodeFromQr(null), isNull);
  });

  testWidgets('mesa aberta: total do servidor, as 9 opções de hoje e nenhuma outra, itens com Transferir e Cancelar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final server = _Server();
    await _login(tester, server);
    await _openTable2(tester);

    // Topo: mesa, cliente, quem abriu e pessoas.
    expect(find.text('Mesa 2'), findsOneWidget);
    expect(find.text('Jefferson · Wanderson · 3 pessoas'), findsOneWidget);

    // Cartão navy: tudo vem do `bill` do servidor.
    expect(find.text('Total da mesa'), findsOneWidget);
    expect(find.text('R\$ 48,40'), findsOneWidget);
    expect(find.text('Itens R\$ 44,00'), findsOneWidget);
    expect(find.text('Taxa de serviço 10% R\$ 4,40'), findsOneWidget);
    expect(find.textContaining('Pago'), findsNothing);

    // Grade 3 x 2: exatamente estas seis, nesta ordem.
    for (final label in _gridOptions) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    final grid = find.byType(ColGrid);
    expect(tester.widget<ColGrid>(grid).cols, 3);
    expect(tester.widget<ColGrid>(grid).children, hasLength(6));
    final spots = [for (final l in _gridOptions) tester.getCenter(find.text(l))];
    expect(spots[0].dy, closeTo(spots[1].dy, 14));
    expect(spots[3].dy, greaterThan(spots[0].dy + 40));
    expect(spots[0].dx < spots[1].dx && spots[1].dx < spots[2].dx, isTrue);

    // Barra trio de largura igual: + Itens, Pedir conta, Receber conta.
    final bar = find.descendant(of: find.byType(BottomBar), matching: find.byType(Btn));
    expect([for (final b in tester.widgetList<Btn>(bar)) b.label], ['+ Itens', 'Pedir conta', 'Receber conta']);
    final widths = {for (final e in bar.evaluate()) tester.getSize(find.byWidget(e.widget)).width.round()};
    expect(widths, hasLength(1));
    expect(tester.getSize(bar.first).height, greaterThanOrEqualTo(44));

    // "Cancelar mesa" à parte, no fim da lista.
    expect(find.text('Cancelar mesa'), findsOneWidget);
    expect(tester.getCenter(find.text('Cancelar mesa')).dy, greaterThan(tester.getCenter(find.text('2x Long neck')).dy));

    // Nada além das 9 de hoje (o que saiu do menu antigo ou nunca existiu).
    for (final absent in [
      'Opções da mesa',
      'Ver itens',
      'Imprimir conta',
      'Reabrir mesa',
      'Fechar mesa',
      'Dividir conta',
      'Desconto',
      'Juntar mesas',
    ]) {
      expect(find.textContaining(absent), findsNothing, reason: absent);
    }

    // Itens: quantidade, nome, observação, status, valor e os dois links.
    expect(find.text('ITENS DA MESA'), findsOneWidget);
    expect(find.text('3 ITENS'), findsOneWidget);
    expect(find.text('2x Long neck'), findsOneWidget);
    expect(find.text('1x X-Burger'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(find.text('aguardando'), findsNWidgets(2));
    expect(find.text('R\$ 22,00'), findsNWidgets(2));
    expect(find.text('Transferir'), findsNWidgets(2));
    expect(find.text('Cancelar'), findsNWidgets(2));
    expect(tester.getSize(find.bySemanticsLabel('Cancelar Long neck')).height, greaterThanOrEqualTo(44));

    // Transferir: a mesma janela de destino de sempre.
    await tester.tap(find.bySemanticsLabel('Transferir X-Burger'));
    await tester.pumpAndSettle();
    expect(find.byType(TransferItemSheet), findsOneWidget);
    expect(find.text('Transferir item'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(Btn, 'Cancelar'));
    await tester.pumpAndSettle();

    // Cancelar: pede o motivo e chama a rota de sempre.
    await tester.tap(find.bySemanticsLabel('Cancelar Long neck'));
    await tester.pumpAndSettle();
    expect(find.byType(CancelItemSheet), findsOneWidget);
    await tester.tap(find.text('Cliente desistiu'));
    await tester.pump();
    await tester.tap(find.widgetWithText(Btn, 'Confirmar'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    final cancel = server.mutations.single;
    expect('${cancel.method} ${cancel.path}', 'DELETE /items/i1');
    expect(cancel.body, {'reason': 'Cliente desistiu'});
    // A conta acompanha o servidor.
    expect(find.text('R\$ 24,20'), findsOneWidget);
    expect(find.text('2x Long neck'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('opção sem permissão continua na grade, apagada, e explica ao toque; nada é chamado', (tester) async {
    final server = _Server(perms: const {'open_session': true, 'create_order': true});
    await _login(tester, server);
    await _openTable2(tester);

    // A grade não muda de forma: as seis opções e a barra de três.
    for (final label in _gridOptions) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.widget<ColGrid>(find.byType(ColGrid)).children, hasLength(6));
    expect(find.descendant(of: find.byType(BottomBar), matching: find.byType(Btn)), findsNWidgets(3));
    // Sem permissão de item, os links da linha não aparecem (como hoje).
    expect(find.text('Transferir'), findsNothing);
    expect(find.text('Cancelar'), findsNothing);

    await tester.tap(find.text('Transferir mesa'));
    await tester.pump();
    expect(find.text('Seu usuário não tem permissão para transferir mesa.'), findsOneWidget);
    expect(find.byType(TransferTableSheet), findsNothing);
    await _toastGone(tester);

    await tester.tap(find.text('Receber conta'));
    await tester.pump();
    expect(find.text('Seu usuário não tem permissão para receber pagamentos.'), findsOneWidget);
    expect(find.byType(ReceiveScreen), findsNothing);
    await _toastGone(tester);

    await tester.tap(find.text('Cancelar mesa'));
    await tester.pump();
    expect(find.text('Seu usuário não tem permissão para cancelar a mesa.'), findsOneWidget);
    expect(find.byType(CancelSessionSheet), findsNothing);
    await _toastGone(tester);

    expect(server.mutations, isEmpty);
    await _unmount(tester);
  });

  testWidgets('gerar QR do tablet: a rota do PWA, o código grande e o QR quando o lado nativo desenha', (tester) async {
    final server = _Server();
    final device = await _login(tester, server);
    await _openTable2(tester);

    // Sem o lado nativo (prévia web, testes): só o código.
    await tester.tap(find.text('Gerar QR do tablet na mesa'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TabletCodeSheet), findsOneWidget);
    expect(find.text('Tablet na mesa · 2'), findsOneWidget);
    expect(find.text('482913'), findsOneWidget);
    expect(find.descendant(of: find.byType(TabletCodeSheet), matching: find.byType(Image)), findsNothing);
    expect(server.mutationPaths, ['POST /sessions/sess2/tablet-code']);
    await tester.tap(find.widgetWithText(Btn, 'Fechar'));
    await tester.pumpAndSettle();

    // Com o lado nativo: o QR do código aparece junto.
    device.drawsQr = true;
    await tester.tap(find.text('Gerar QR do tablet na mesa'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('482913'), findsOneWidget);
    expect(find.descendant(of: find.byType(TabletCodeSheet), matching: find.byType(Image)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('pedir conta: a ação de sempre, a mesa vira "fechando" e o app volta ao mapa com o aviso', (
    tester,
  ) async {
    final server = _Server();
    await _login(tester, server);
    await _openTable2(tester);

    await tester.tap(find.widgetWithText(Btn, 'Pedir conta'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.mutationPaths, ['POST /tables/t2/sessions/current/bill']);
    expect(find.byType(SessionScreen), findsNothing);
    expect(find.text('Conta da mesa 2 pedida · mesa em fechamento'), findsOneWidget);
    expect(find.text('Fechando 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    // De volta à mesa: o estado "fechando" fica claro, com "Reabrir mesa".
    await tester.tap(_tableCard('2'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Conta solicitada. Aguardando pagamento.'), findsOneWidget);
    expect(find.text('Reabrir mesa'), findsOneWidget);
    // "+ Itens" e "Pedir conta" continuam na barra, apagados.
    await tester.tap(find.text('Pedir conta'));
    await tester.pump();
    expect(find.text('A conta desta mesa já foi pedida.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Reabrir mesa'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(server.mutationPaths.last, 'POST /sessions/sess2/reopen');
    expect(find.text('Conta solicitada. Aguardando pagamento.'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
    'receber conta: parcial registra e continua na tela com o novo restante; o total fecha a mesa e mostra "Conta paga"',
    (tester) async {
      final server = _Server();
      await _login(tester, server);
      await _openReceive(tester);

      expect(find.text('Receber conta'), findsOneWidget);
      expect(find.text('Mesa 2 · 3 pessoas'), findsOneWidget);
      expect(find.text('Valor restante'), findsOneWidget);
      expect(find.text('R\$ 48,40'), findsOneWidget);
      expect(find.text('pago R\$ 0,00'), findsOneWidget);
      expect(find.text('total R\$ 48,40'), findsOneWidget);
      expect(find.text('Itens'), findsOneWidget);
      expect(find.text('Taxa de serviço 10%'), findsOneWidget);
      // As formas são as cadastradas na loja, em grade de 3.
      for (final m in ['Dinheiro', 'Crédito', 'Débito', 'Pix']) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      expect(find.text('Pix online'), findsNothing);
      expect(tester.widget<ColGrid>(find.byType(ColGrid)).cols, 3);
      expect(tester.widget<TextField>(_field('Valor')).controller!.text, '48,40');

      // 1º pagamento: Pix parcial de R$ 20,00.
      await tester.tap(find.text('Pix'));
      await tester.pump();
      await tester.enterText(_field('Valor'), '20,00');
      await tester.pump();
      expect(_barButton(tester).label, 'Receber R\$ 20,00 em Pix');
      await _tapBar(tester);
      expect(server.mutationPaths, ['POST /sessions/sess2/payments']);
      expect(server.mutations.single.body, {'method': 'pix', 'amount': 20.0});
      // Continua na tela, com o que o servidor devolveu.
      expect(find.byType(ReceiveScreen), findsOneWidget);
      expect(find.text('R\$ 28,40'), findsOneWidget);
      expect(find.text('pago R\$ 20,00'), findsOneWidget);
      expect(find.text('Pagamento 1 · Pix'), findsOneWidget);
      expect(tester.widget<TextField>(_field('Valor')).controller!.text, '28,40');
      expect(find.text('Conta paga!'), findsNothing);

      // 2º pagamento: o restante em dinheiro, com troco.
      await tester.tap(find.text('Dinheiro'));
      await tester.pump();
      expect(tester.widget<TextField>(_field('Valor recebido')).controller!.text, '28,40');
      await tester.enterText(_field('Valor recebido'), '30,00');
      await tester.pump();
      expect(find.text('R\$ 1,60'), findsOneWidget);
      expect(_barButton(tester).label, 'Receber R\$ 28,40 em Dinheiro');
      await _tapBar(tester);
      expect(server.mutations.last.body, {'method': 'cash', 'amount': 28.4, 'cash_received': 30.0});

      // Conta paga: total recebido, os pagamentos desta operação e o troco.
      expect(find.text('Conta paga'), findsOneWidget);
      expect(find.text('Conta paga!'), findsOneWidget);
      expect(find.text('R\$ 48,40 recebidos em 2 pagamentos'), findsOneWidget);
      expect(find.text('Pagamento 1'), findsOneWidget);
      expect(find.text('Pagamento 2'), findsOneWidget);
      expect(find.text('Pix'), findsOneWidget);
      expect(find.text('Dinheiro'), findsOneWidget);
      expect(find.text('Troco: R\$ 1,60'), findsOneWidget);
      expect(find.text('Aguardando fechamento da mesa.'), findsNothing);
      expect(server.status, 'closed');

      await tester.tap(find.widgetWithText(Btn, 'Voltar às mesas'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveScreen), findsNothing);
      expect(find.byType(SessionScreen), findsNothing);
      expect(find.bySemanticsLabel('Mesa 2, livre'), findsOneWidget);
      expect(find.text('Livres 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets('dinheiro exige o valor recebido; valor acima do restante só em dinheiro', (tester) async {
    final server = _Server();
    await _login(tester, server);
    await _openReceive(tester);

    await tester.tap(find.text('Dinheiro'));
    await tester.pump();
    expect(find.text('Valor recebido'), findsOneWidget);
    expect(find.text('Troco'), findsOneWidget);
    await tester.enterText(_field('Valor recebido'), '10,00');
    await tester.pump();
    await _tapBar(tester);
    expect(find.text('O valor recebido é menor que o valor a pagar.'), findsOneWidget);
    expect(server.mutations, isEmpty);
    expect(find.byType(ReceiveScreen), findsOneWidget);

    // Outra forma não tem "Valor recebido" e não passa do restante.
    await tester.tap(find.text('Débito'));
    await tester.pump();
    expect(find.text('Valor recebido'), findsNothing);
    await tester.enterText(_field('Valor'), '60,00');
    await tester.pump();
    await _tapBar(tester);
    expect(
      find.text('O valor não pode passar do restante (R\$ 48,40). Só dinheiro dá troco.'),
      findsOneWidget,
    );
    await tester.enterText(_field('Valor'), '0');
    await tester.pump();
    await _tapBar(tester);
    expect(find.text('Informe o valor.'), findsOneWidget);
    expect(server.mutations, isEmpty);
    await _unmount(tester);
  });

  testWidgets('cartão na maquininha: cobra pelo TefLedger e registra com os campos de TEF e chave de idempotência', (
    tester,
  ) async {
    final server = _Server();
    final device = await _login(tester, server, stone: true);
    device.stoneReturn =
        'mobizpos://pay-response?code=0&amount=4840&atk=37820073187607&authorization_code=187607'
        '&brand=MASTERCARD&pan=627303****2166&type=Cr%C3%A9dito';
    await _openReceive(tester);

    // Com a maquininha, a forma padrão é a primeira cobrada nela.
    expect(_barButton(tester).label, 'Cobrar R\$ 48,40 em Crédito');
    expect(find.text('A cobrança abre o app de pagamento da maquininha.'), findsOneWidget);
    await _tapBar(tester);

    // Deeplink da Stone: centavos exatos e tipo CREDIT.
    final link = Uri.parse(device.launched.single);
    expect(link.scheme, 'payment-app');
    expect(link.queryParameters['amount'], '4840');
    expect(link.queryParameters['transaction_type'], 'CREDIT');

    final pay = server.mutations.single;
    expect('${pay.method} ${pay.path}', 'POST /sessions/sess2/payments');
    expect(pay.headers['Idempotency-Key'], isNotEmpty);
    expect(pay.body['method'], 'credit_card');
    expect(pay.body['amount'], 48.4);
    expect(pay.body['tef_provider'], 'stone_deeplink');
    expect(pay.body['tef_transaction_id'], '37820073187607');
    expect(pay.body['tef_nsu'], '187607');
    expect(pay.body['reference'], 'MASTERCARD ****2166');
    expect(app.ledger.pending, isEmpty);

    expect(find.text('Conta paga!'), findsOneWidget);
    expect(find.text('R\$ 48,40 recebidos em 1 pagamento'), findsOneWidget);
    expect(find.text('Crédito'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('maquininha recusa: nada é registrado e a tela mostra o motivo; sem resposta vira pendência', (
    tester,
  ) async {
    final server = _Server();
    final device = await _login(tester, server, stone: true);
    device.stoneReturn = 'mobizpos://pay-response?success=false&code=-6&message=N%C3%A3o%20autorizada';
    await _openReceive(tester);
    await _tapBar(tester);
    expect(find.text('Não autorizada'), findsOneWidget);
    expect(server.mutations, isEmpty);
    expect(app.ledger.pending, isEmpty);
    expect(find.byType(ReceiveScreen), findsOneWidget);

    // Sem resposta (o operador voltou e nada aconteceu): o aviso de sempre e a pendência guardada.
    device.stoneReturn = null;
    await _tapBar(tester);
    await tester.pumpAndSettle();
    expect(find.text('Sem resposta da maquininha'), findsOneWidget);
    expect(find.textContaining('Confira no app da Stone se a cobrança foi aprovada'), findsOneWidget);
    await tester.tap(find.widgetWithText(Btn, 'Entendi'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveScreen), findsNothing);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(app.ledger.pending.single.state, 'unknown');
    expect(server.mutations, isEmpty);
    await _unmount(tester);
  });

  testWidgets('conta quitada sem a mesa fechar: "Conta paga" mantém o aviso e o "Fechar mesa" de quem pode', (
    tester,
  ) async {
    final server = _Server()..closesWhenPaid = false;
    await _login(tester, server);
    await _openReceive(tester);
    await tester.tap(find.text('Pix'));
    await tester.pump();
    await _tapBar(tester);

    expect(find.text('Conta paga!'), findsOneWidget);
    expect(find.text('Conta quitada. Aguardando fechamento da mesa.'), findsOneWidget);
    await tester.tap(find.widgetWithText(Btn, 'Fechar mesa'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(server.mutationPaths.last, 'POST /sessions/sess2/close');
    expect(find.text('Conta quitada. Aguardando fechamento da mesa.'), findsNothing);
    expect(find.widgetWithText(Btn, 'Voltar às mesas'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('mesa com comandas: "Receber conta" leva às Comandas da mesa e o recebimento é por comanda', (
    tester,
  ) async {
    final server = _Server(comandas: true);
    await _login(tester, server);
    await _openTable2(tester);
    expect(find.text('Comanda Ana · às '), findsNothing);
    expect(find.textContaining('Comanda Ana'), findsOneWidget);

    await tester.tap(find.widgetWithText(Btn, 'Receber conta'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveScreen), findsNothing);
    expect(find.text('Comandas da mesa'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(Btn, 'Receber'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveScreen), findsOneWidget);
    expect(find.text('Mesa 2 · Comanda Ana'), findsOneWidget);
    expect(find.text('R\$ 24,20'), findsOneWidget);
    expect(find.text('total R\$ 24,20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('balcão em duas formas: a parte menor fica na tela e a venda só é gravada quando cobre o total', (
    tester,
  ) async {
    final server = _Server();
    await _login(tester, server);
    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Balcão')));
    await _settle(tester);
    await tester.pumpAndSettle();
    final plus = find.descendant(of: find.byKey(const ValueKey('guarana')), matching: find.byIcon(Icons.add));
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(find.byType(CountBtn));
    await tester.pumpAndSettle();
    expect(find.byType(CounterSaleScreen), findsOneWidget);
    await tester.tap(find.byType(CountBtn));
    await tester.pumpAndSettle();

    expect(find.byType(ReceiveScreen), findsOneWidget);
    expect(find.text('Receber venda'), findsOneWidget);
    expect(find.text('Balcão · Bar do Zé'), findsOneWidget);
    expect(find.text('total R\$ 14,00'), findsOneWidget);
    expect(find.text('Taxa de serviço 10%'), findsNothing);
    expect(find.text('Cliente (opcional)'), findsOneWidget);
    for (final m in ['Dinheiro', 'Débito', 'Crédito']) {
      expect(find.text(m), findsOneWidget, reason: m);
    }
    expect(_barButton(tester).label, 'Receber R\$ 14,00 em Dinheiro');

    // Parte 1: R$ 4,00 em débito. Nada vai ao servidor ainda.
    await tester.tap(find.text('Débito'));
    await tester.pump();
    await tester.enterText(_field('Valor'), '4,00');
    await tester.pump();
    await _tapBar(tester);
    expect(server.mutations, isEmpty);
    expect(find.byType(ReceiveScreen), findsOneWidget);
    expect(find.text('R\$ 10,00'), findsOneWidget);
    expect(find.text('pago R\$ 4,00'), findsOneWidget);
    expect(find.text('Pagamento 1 · Débito'), findsOneWidget);

    // Parte 2: o restante em dinheiro, com o nome do cliente.
    await tester.tap(find.text('Dinheiro'));
    await tester.pump();
    await tester.enterText(_field('Cliente (opcional)'), 'Carlos');
    expect(_barButton(tester).label, 'Receber R\$ 10,00 em Dinheiro');
    await _tapBar(tester);
    final checkout = server.mutations.single;
    expect(checkout.path, '/counter/checkout');
    expect(checkout.headers['Idempotency-Key'], isNotEmpty);
    expect(checkout.body['customer_name'], 'Carlos');
    expect(checkout.body['payments'], [
      {'method': 'debit_card', 'amount': 4.0},
      {'method': 'cash', 'amount': 10.0},
    ]);
    expect(checkout.body['items'], [
      {'product_id': 'guarana', 'quantity': 2},
    ]);

    // Venda recebida, e daqui para uma nova venda.
    expect(find.text('Venda recebida'), findsOneWidget);
    expect(find.text('Venda recebida!'), findsOneWidget);
    expect(find.text('R\$ 14,00 recebidos em 2 pagamentos'), findsOneWidget);
    expect(find.text('Venda #101'), findsOneWidget);
    expect(find.text('Débito'), findsOneWidget);
    expect(find.text('Dinheiro'), findsOneWidget);
    await tester.tap(find.widgetWithText(Btn, 'Nova venda de balcão'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveScreen), findsNothing);
    expect(find.byType(CounterSaleScreen), findsNothing);
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(tester.widget<CountBtn>(find.byType(CountBtn)).onTap, isNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('balcão com cartão: cobra na maquininha (chargeOnly) e o checkout leva o ATK e o NSU', (tester) async {
    final server = _Server();
    final device = await _login(tester, server, stone: true);
    device.stoneReturn = 'mobizpos://pay-response?code=0&amount=1400&atk=999111&authorization_code=4455&brand=VISA';
    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Balcão')));
    await _settle(tester);
    await tester.pumpAndSettle();
    final plus = find.descendant(of: find.byKey(const ValueKey('guarana')), matching: find.byIcon(Icons.add));
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(find.byType(CountBtn));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CountBtn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Débito'));
    await tester.pump();
    expect(_barButton(tester).label, 'Cobrar R\$ 14,00 em Débito');
    await _tapBar(tester);
    expect(Uri.parse(device.launched.single).queryParameters['transaction_type'], 'DEBIT');
    expect(server.mutations.single.body['payments'], [
      {'method': 'debit_card', 'amount': 14.0, 'tef_transaction_id': '999111', 'tef_nsu': '4455'},
    ]);
    expect(find.text('Venda recebida!'), findsOneWidget);
    // Venda gravada: a cobrança deixa de estar pendente.
    expect(app.ledger.pending, isEmpty);
    await _unmount(tester);
  });

  testWidgets('ler QR da comanda: a câmera preenche o código e confere no servidor; sem câmera, segue digitando', (
    tester,
  ) async {
    final server = _Server();
    final device = await _login(tester, server);
    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Mais')));
    await _settle(tester);
    await tester.tap(find.text('Ler QR da comanda'));
    await tester.pumpAndSettle();
    expect(find.byType(ComandaLinkSheet), findsOneWidget);
    expect(find.widgetWithText(Btn, 'Ler com a câmera'), findsOneWidget);
    expect(find.text('OU DIGITE O CÓDIGO DA COMANDA'), findsOneWidget);

    // Permissão negada: aviso, nada vai ao servidor e o campo continua lá.
    device.scanError = 'denied';
    await tester.tap(find.widgetWithText(Btn, 'Ler com a câmera'));
    await _settle(tester, 2);
    expect(find.textContaining('A câmera não foi liberada para o app'), findsOneWidget);
    expect(server.mutations, isEmpty);
    expect(find.byType(TextField), findsOneWidget);

    // Aparelho sem câmera.
    device.scanError = 'no_camera';
    await tester.tap(find.widgetWithText(Btn, 'Ler com a câmera'));
    await _settle(tester, 2);
    expect(find.text('Este aparelho não tem câmera. Digite o código da comanda.'), findsOneWidget);

    // Voltou sem ler: nada muda.
    device
      ..scanError = null
      ..scan = null;
    await tester.tap(find.widgetWithText(Btn, 'Ler com a câmera'));
    await _settle(tester, 2);
    expect(find.textContaining('câmera.'), findsNothing);
    expect(server.mutations, isEmpty);

    // Leu o QR: o conteúdo (sem espaços das pontas) vai para a rota de sempre.
    device.scan = ' 101\n';
    await tester.tap(find.widgetWithText(Btn, 'Ler com a câmera'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(device.scanPrompts.last, 'Aponte para o QR da comanda');
    final lookup = server.mutations.single;
    expect('${lookup.method} ${lookup.path}', 'POST /tablet/comandas/lookup');
    expect(lookup.body, {'code': '101'});
    expect(find.text('Comanda 101'), findsOneWidget);
    expect(find.widgetWithText(Btn, 'Vincular à mesa'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  test('controlador do balcão: troco só em dinheiro, parte não cobrada sai da lista, cobre o total antes de gravar', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final server = _Server();
    final boot = await App.boot(
      backend: MemoryBackend()..values['server_input'] = 'bardoze',
      client: MockClient(server.handle),
      probeDevice: false,
    );
    final c = CounterReceiveController(
      saleTotal: 30,
      options: const [],
      parts: [],
      items: const [],
      cartKey: 'k1',
      counter: boot.counter,
      ledger: boot.ledger,
      terminal: boot.terminal,
    );
    // Loja sem forma cadastrada: cai em dinheiro, como antes.
    expect(c.methods, isEmpty);
    expect(c.selected.isCash, isTrue);
    expect(c.remaining, 30);
    expect(c.changeFor(50), 20);
    expect(c.changeFor(10), 0);

    expect((await c.receive(amount: 0)).kind, ReceiveOutcomeKind.failed);
    expect(c.error, 'Informe o valor.');

    expect((await c.receive(amount: 10)).kind, ReceiveOutcomeKind.partial);
    expect(c.remaining, 20);
    expect(c.covered, isFalse);
    expect(server.mutations, isEmpty);
    c.removePart(0);
    expect(c.remaining, 30);

    final done = await c.receive(amount: 50, customer: '  ');
    expect(done.kind, ReceiveOutcomeKind.done);
    expect(c.sale?.number, 101);
    final checkout = server.mutations.single;
    expect(checkout.headers['Idempotency-Key'], 'k1');
    expect(checkout.body.containsKey('customer_name'), isFalse);
    expect(checkout.body['payments'], [
      {'method': 'cash', 'amount': 50.0},
    ]);
    c.dispose();
  });
}
