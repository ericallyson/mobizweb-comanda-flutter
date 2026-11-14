// Cardápio, montagem e revisão do pedido (seções 5.2 a 5.4 do layout novo) e a
// venda de balcão (5.7): o "+" lança direto, a pizza respeita mínimo/máximo, a
// mesa livre só é aberta no servidor ao enviar e a observação vai no payload.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/addon_rules.dart';
import 'package:mobizweb_pos/core/product_builder.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/main.dart';
import 'package:mobizweb_pos/models/models.dart';
import 'package:mobizweb_pos/stores/order_draft.dart';
import 'package:mobizweb_pos/ui/kit.dart';
import 'package:mobizweb_pos/ui/screens/counter_screen.dart';
import 'package:mobizweb_pos/ui/screens/menu_screen.dart';
import 'package:mobizweb_pos/ui/screens/receive_screen.dart';
import 'package:mobizweb_pos/ui/screens/review_screen.dart';
import 'package:mobizweb_pos/ui/screens/session_screen.dart';
import 'package:mobizweb_pos/ui/table_card.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _perms = {
  'open_session': true,
  'create_order': true,
  'request_bill': true,
  'counter_sale': true,
  'process_payment': true,
};

Map<String, dynamic> _product(String id, String name, double price, [Map<String, dynamic> extra = const {}]) => {
  'id': id,
  'name': name,
  'type': 'simple',
  'price': price,
  'is_available': true,
  'unit_of_measure': 'un',
  'allow_fractional_qty': false,
  'addon_groups': <dynamic>[],
  ...extra,
};

final _pizzaJson = _product('pizza', 'Pizza Grande', 0, {
  'type': 'pizza',
  'pizza': {
    'max_flavors': 2,
    'pricing_rule': 'highest',
    'flavor_group': {
      'id': 'fg',
      'name': 'Sabores',
      'items': [
        {'id': 'f-cal', 'name': 'Calabresa', 'price': 49},
        {'id': 'f-mus', 'name': 'Mussarela', 'price': 47},
        {'id': 'f-por', 'name': 'Portuguesa', 'price': 56},
      ],
    },
  },
  'addon_groups': [
    {
      'id': 'g-borda',
      'name': 'Borda',
      'min': 0,
      'max': 1,
      'is_required': false,
      'items': [
        {'id': 'b-cat', 'name': 'Catupiry', 'price': 10, 'max_quantity': 1},
        {'id': 'b-che', 'name': 'Cheddar', 'price': 8, 'max_quantity': 1},
      ],
    },
  ],
});

final _burgerJson = _product('burger', 'X-Burger', 22, {
  'addon_groups': [
    {
      'id': 'g-ponto',
      'name': 'Ponto da carne',
      'min': 1,
      'max': 1,
      'is_required': true,
      'items': [
        {'id': 'p-mal', 'name': 'Mal passado', 'price': 0},
        {'id': 'p-ao', 'name': 'Ao ponto', 'price': 0},
      ],
    },
    {
      'id': 'g-extra',
      'name': 'Adicionais',
      'min': 0,
      'max': 2,
      'is_required': false,
      'items': [
        {'id': 'e-bacon', 'name': 'Bacon', 'price': 4, 'max_quantity': 3, 'item_limit': 3},
        {'id': 'e-ovo', 'name': 'Ovo', 'price': 2.5},
      ],
    },
  ],
});

final _comboJson = _product('combo', 'Combo X', 34.9, {
  'type': 'combo',
  'combo_groups': [
    {
      'id': 'cg-beb',
      'name': 'Bebida',
      'min': 1,
      'max': 1,
      'is_required': true,
      'items': [
        {'id': 'ci-refri', 'name': 'Refrigerante', 'product_id': 'guarana', 'extra_price': 0, 'is_default': false},
        {'id': 'ci-suco', 'name': 'Suco', 'product_id': 'suco', 'extra_price': 3, 'is_default': false},
      ],
    },
  ],
});

/// Cardápio com hierarquia: "Bebidas" tem as subcategorias "Sem álcool" e
/// "Cervejas". [extraRoots] acrescenta categorias raiz vazias.
List<Map<String, dynamic>> _menu({int extraRoots = 0}) => [
  {'id': 'c-beb', 'name': 'Bebidas', 'parent_id': null, 'products': <dynamic>[]},
  {
    'id': 'c-piz',
    'name': 'Pizzas',
    'parent_id': null,
    'products': [_pizzaJson],
  },
  {
    'id': 'c-lan',
    'name': 'Lanches',
    'parent_id': null,
    'products': [_burgerJson, _comboJson],
  },
  {
    'id': 'c-por',
    'name': 'Porções',
    'parent_id': null,
    'products': [
      _product('picanha', 'Picanha no quilo', 189.9, {'unit_of_measure': 'kg', 'allow_fractional_qty': true}),
      _product('brownie', 'Brownie', 14, {'is_available': false}),
    ],
  },
  {
    'id': 'c-sem',
    'name': 'Sem álcool',
    'parent_id': 'c-beb',
    'products': [_product('guarana', 'Guaraná Lata', 7), _product('suco', 'Suco de Laranja', 12)],
  },
  {
    'id': 'c-cer',
    'name': 'Cervejas',
    'parent_id': 'c-beb',
    'products': [_product('long', 'Long neck', 11)],
  },
  for (var i = 0; i < extraRoots; i++) {'id': 'x$i', 'name': 'Extra $i', 'parent_id': null, 'products': <dynamic>[]},
];

typedef _Call = ({String method, String path, Map<String, dynamic> body, String? key});

/// Mini-servidor em memória que GUARDA as chamadas, para conferir a ordem.
class _Server {
  _Server({this.extraRoots = 0});
  final int extraRoots;
  final calls = <_Call>[];

  /// Quantas vezes o `POST /sessions/{id}/orders` ainda deve falhar (500).
  int failOrders = 0;
  bool kitchenSent = true;
  bool counterEnabled = true;

  /// Sessões abertas por mesa (id da mesa → sessão).
  final sessions = <String, Map<String, dynamic>>{
    't2': {
      'id': 'sess2',
      'status': 'open',
      'guest_count': 3,
      'customer_name': 'Jefferson',
      'table': {'id': 't2', 'number': '2', 'label': 'Mesa 2'},
      'has_comandas': false,
      'comandas': <dynamic>[],
      'items': <Map<String, dynamic>>[
        {'id': 'i1', 'product_name': 'Long neck', 'quantity': 2, 'unit_price': 11, 'status': 'pending'},
      ],
      'bill': {'items_subtotal': 22, 'total': 24.2, 'remaining': 24.2},
    },
  };

  Iterable<_Call> get mutations => calls.where((c) => c.method != 'GET');
  List<String> get mutationPaths => [for (final c in mutations) '${c.method} ${c.path}'];

  Map<String, dynamic>? _sessionById(String id) => sessions.values.where((s) => s['id'] == id).firstOrNull;

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/api/garcom/v1', '');
    final body = req.body.isEmpty ? <String, dynamic>{} : (jsonDecode(req.body) as Map).cast<String, dynamic>();
    calls.add((method: req.method, path: path, body: body, key: req.headers['Idempotency-Key']));

    if (path == '/auth/login') {
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
    switch (path) {
      case '/auth/me':
        return _json(200, {'permissions': _perms});
      case '/tables':
        return _json(200, {
          'settings': {'enable_comandas': true, 'idle_alert_minutes': 0},
          'tables': [
            for (final n in ['1', '2'])
              {
                'id': 't$n',
                'number': n,
                'label': 'Mesa $n',
                'status': sessions.containsKey('t$n') ? 'occupied' : 'available',
                if (sessions.containsKey('t$n'))
                  'session': {
                    'id': sessions['t$n']!['id'],
                    'status': 'open',
                    'opened_at': '2026-11-14T12:00:00Z',
                    'guest_count': sessions['t$n']!['guest_count'],
                    'customer_name': sessions['t$n']!['customer_name'],
                    'total': 10,
                  },
              },
          ],
        });
      case '/tablet/calls':
        return _json(200, {'calls': <dynamic>[], 'pending_orders': <dynamic>[], 'low_stock_alerts': <dynamic>[]});
      case '/menu':
        return _json(200, {'categories': _menu(extraRoots: extraRoots)});
      case '/payment-methods':
        return _json(200, {'payment_methods': <dynamic>[], 'pix_online': null});
      case '/counter/context':
        return _json(200, {
          'enabled': counterEnabled,
          'permissions': {'sell': true},
          'payment_methods': [
            {'id': 'm1', 'name': 'Dinheiro', 'code': 'cash', 'method': 'cash', 'is_default': true, 'is_cash': true},
          ],
          'cash_session': null,
        });
      case '/counter/checkout':
        return _json(201, {
          'order': {'id': 'o1', 'number': 101, 'total': 14, 'change_amount': 0},
          'receipt': {'status': 'skipped', 'requires_operator_decision': false},
        });
    }

    final open = RegExp(r'^/tables/(\w+)/sessions$').firstMatch(path);
    if (open != null && req.method == 'POST') {
      final tableId = open.group(1)!;
      final labels = [for (final l in (body['comandas'] as List? ?? const [])) '$l'];
      final session = sessions.putIfAbsent(
        tableId,
        () => {
          'id': 's-new',
          'status': 'open',
          'guest_count': body['guest_count'],
          'customer_name': body['customer_name'],
          'table': {'id': tableId, 'number': '1', 'label': 'Mesa 1'},
          'has_comandas': labels.isNotEmpty,
          'comandas': [
            for (final l in labels) {'id': 'cmd-$l', 'label': l, 'status': 'open'},
          ],
          'items': <dynamic>[],
          'bill': <String, dynamic>{},
        },
      );
      return _json(201, {
        'session': {'id': session['id']},
      });
    }

    final sessionPath = RegExp(r'^/sessions/([\w-]+)(/\w+)?$').firstMatch(path);
    if (sessionPath != null) {
      final session = _sessionById(sessionPath.group(1)!);
      if (session == null) return _json(404, {'error': 'Mesa não encontrada.'});
      switch (sessionPath.group(2)) {
        case null:
          return _json(200, {'session': session});
        case '/orders':
          if (failOrders > 0) {
            failOrders -= 1;
            return _json(500, {'message': 'erro'});
          }
          final items = session['items'] as List;
          for (final it in body['items'] as List) {
            items.add({
              'id': 'n${items.length}',
              'product_name': it['product_id'],
              'quantity': it['quantity'],
              'unit_price': 1,
              'notes': it['notes'],
              'status': 'pending',
              'comanda_id': body['session_comanda_id'],
            });
          }
          return _json(201, {
            'order': {'id': 'ord', 'code': '1001'},
            'kitchen_sent': kitchenSent,
          });
        case '/customer':
          session['customer_name'] = body['customer_name'];
          return _json(200, {'customer_name': body['customer_name']});
      }
    }
    return _json(404, {'message': 'not found'});
  }
}

Future<void> _boot(WidgetTester tester, _Server server) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(
    () => App.boot(
      backend: MemoryBackend()..values['server_input'] = 'bardoze',
      client: MockClient(server.handle),
      probeDevice: false,
    ),
  );
}

/// Deixa as chamadas HTTP falsas terminarem e redesenha.
Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _login(WidgetTester tester, _Server server) async {
  await _boot(tester, server);
  await tester.pumpWidget(const MobizApp());
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(0), 'ana@x.com');
  await tester.enterText(find.byType(TextField).at(1), '123456');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await _settle(tester);
}

/// Tira a árvore da tela para os timers de polling serem cancelados.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Finder _tableCard(String number) => find.byWidgetPredicate((w) => w is TableCard && w.table.number == number);

/// Cartão do produto no cardápio (a chave é o id do produto).
Finder _productCard(String id) => find.byKey(ValueKey(id));

/// O "+" do cartão do produto.
Finder _plus(String id) => find.descendant(of: _productCard(id), matching: find.byIcon(Icons.add));
Finder _minus(String id) => find.descendant(of: _productCard(id), matching: find.byIcon(Icons.remove));

/// Bloco de categoria (o texto vai em maiúsculas).
Future<void> _category(WidgetTester tester, String name) async {
  await tester.tap(find.text(name.toUpperCase()));
  await tester.pump();
}

Future<void> _openFreeTable(WidgetTester tester) async {
  await tester.tap(_tableCard('1'));
  await _settle(tester);
  await tester.pumpAndSettle();
}

MenuProduct get _pizza => MenuProduct.fromJson(_pizzaJson);
MenuProduct get _burger => MenuProduct.fromJson(_burgerJson);
MenuProduct get _combo => MenuProduct.fromJson(_comboJson);

void main() {
  group('montagem do item (ProductBuilder)', () {
    test('pizza: bloqueia até escolher sabor, respeita o máximo e cobra o maior sabor mais a borda', () {
      final b = ProductBuilder(_pizza);
      expect(needsBuilder(_pizza), isTrue);
      expect(b.blockReason, flavorRequiredMessage);
      expect(b.build(), isNull);

      b.toggleFlavor('f-cal');
      expect(b.blockReason, isNull);
      expect(b.unitPrice, 49);
      b.toggleFlavor('f-por');
      expect(b.unitPrice, 56);
      // No limite, os demais ficam desabilitados e o toque não entra.
      expect(b.canToggleFlavor('f-mus'), isFalse);
      expect(b.canToggleFlavor('f-cal'), isTrue);
      b.toggleFlavor('f-mus');
      expect(b.flavors, {'f-cal', 'f-por'});

      // Borda é escolha única: a segunda troca a primeira.
      final borda = _pizza.addonGroups.single;
      b.toggleAddon(borda, borda.items[0]);
      b.toggleAddon(borda, borda.items[1]);
      expect(b.buildAddons().map((a) => a.addonGroupItemId), ['b-che']);
      b.toggleAddon(borda, borda.items[0]);
      expect(b.unitPrice, 66);

      b.notes = '  bem assada ';
      final item = b.build()!;
      expect(item.selectedFlavorIds, ['f-cal', 'f-por']);
      expect(item.unitPrice, 66);
      expect(item.toPayload(), {
        'product_id': 'pizza',
        'quantity': 1,
        'notes': 'bem assada',
        'addons': [
          {'addon_group_item_id': 'b-cat', 'quantity': 1},
        ],
        'selected_flavor_ids': ['f-cal', 'f-por'],
      });
    });

    test('adicional obrigatório bloqueia; opcional respeita o máximo do grupo e o limite do item', () {
      final b = ProductBuilder(_burger);
      final ponto = _burger.addonGroups[0];
      final extra = _burger.addonGroups[1];
      expect(needsBuilder(_burger), isTrue);
      expect(b.blockReason, requiredAddonsMessage);

      b.toggleAddon(ponto, ponto.items[1]);
      expect(b.blockReason, isNull);

      // Grupo "Adicionais" com máximo 2: dois bacons enchem o grupo.
      b.incAddon(extra, extra.items[0]);
      b.incAddon(extra, extra.items[0]);
      expect(b.canIncAddon(extra, extra.items[0]), isFalse);
      expect(b.canToggleAddon(extra, extra.items[1]), isFalse);
      b.incAddon(extra, extra.items[0]);
      expect(b.addonQty(extra.id, 'e-bacon'), 2);
      expect(b.unitPrice, 30);
      expect(b.addonSummary.map((g) => '${g.group}: ${g.items}'), ['Ponto da carne: Ao ponto', 'Adicionais: 2× Bacon']);
    });

    test('combo: opção obrigatória bloqueia e o acréscimo entra no preço', () {
      final b = ProductBuilder(_combo);
      final bebida = _combo.comboGroups.single;
      expect(needsBuilder(_combo), isTrue);
      expect(b.blockReason, comboRequiredMessage);
      b.toggleCombo(bebida, bebida.items[1]);
      expect(b.blockReason, isNull);
      expect(b.unitPrice, closeTo(37.9, 0.001));
      expect(b.build()!.comboSelections.single.items.single, (id: 'suco', name: 'Suco'));
    });

    test('produto por peso: bloqueia sem peso e guarda três casas', () {
      final p = MenuProduct.fromJson(
        _product('p', 'Picanha', 100, {'allow_fractional_qty': true, 'unit_of_measure': 'kg'}),
      );
      final b = ProductBuilder(p);
      expect(needsBuilder(p), isFalse);
      expect(b.blockReason, weightRequiredMessage);
      b.setWeight('0,3504');
      expect(b.quantity, 0.35);
      expect(b.blockReason, isNull);
      expect(b.total, closeTo(35, 0.001));
    });
  });

  group('preço do cardápio com promoção', () {
    test('lê o preço cobrado, o preço sem promoção, o nome e o código do produto', () {
      final p = MenuProduct.fromJson(
        _product('lata', 'Refrigerante lata', 5.4, {'original_price': 6, 'promotion': 'Happy hour', 'sku': '1001'}),
      );
      expect((p.price, p.originalPrice, p.promotion, p.code), (5.4, 6.0, 'Happy hour', '1001'));
      expect(p.onPromotion, isTrue);
      // O carrinho soma o preço cobrado, que é o que o servidor grava.
      final cart = OrderCart()..addOne(p);
      expect(cart.total, 5.4);
    });

    test('servidor antigo ou produto sem promoção: nada muda', () {
      final p = MenuProduct.fromJson(_product('lata', 'Refrigerante lata', 6));
      expect((p.originalPrice, p.promotion, p.code, p.onPromotion), (null, null, null, false));
      final same = MenuProduct.fromJson(_product('lata', 'Refrigerante lata', 6, {'original_price': 6, 'promotion': null}));
      expect(same.onPromotion, isFalse);
    });
  });

  group('carrinho (OrderCart)', () {
    final guarana = MenuProduct.fromJson(_product('guarana', 'Guaraná Lata', 7));

    test('"+" soma na mesma linha, "−" tira até remover e a chave só troca ao confirmar ou descartar', () {
      final cart = OrderCart();
      final key = cart.key;
      expect(cart.addOne(guarana), isTrue);
      expect(cart.addOne(guarana), isTrue);
      expect(cart.items, hasLength(1));
      expect(cart.qtyOf('guarana'), 2);
      expect(cart.total, 14);
      cart.removeOne('guarana');
      cart.removeOne('guarana');
      expect(cart.isEmpty, isTrue);
      // Esvaziar na mão não é outro carrinho: a chave continua.
      expect(cart.key, key);
      cart.addOne(guarana);
      cart.commit();
      expect(cart.isEmpty, isTrue);
      expect(cart.key, isNot(key));
    });

    test('item com observação fica em linha própria; travado não muda', () {
      final cart = OrderCart()..addOne(guarana);
      cart.add(CartItem(localId: 'a', product: guarana, quantity: 2, notes: 'sem gelo', unitPrice: 7));
      cart.add(CartItem(localId: 'b', product: guarana, quantity: 1, notes: 'sem gelo', unitPrice: 7));
      expect(cart.items.map((i) => '${i.quantity.toInt()} ${i.notes}'), ['1 ', '3 sem gelo']);
      expect(cart.count, 4);

      cart.lockReason = 'Há pagamento já cobrado';
      expect(cart.addOne(guarana), isFalse);
      cart.removeOne('guarana');
      cart.changeQty(cart.items.first, 1);
      expect(cart.count, 4);
    });
  });

  testWidgets('produto que saiu do cardápio bloqueia o envio e nada vai ao servidor', (tester) async {
    final server = _Server();
    await _boot(tester, server);
    await tester.runAsync(() => app.menu.fetch());
    final table = const DiningTable(id: 't1', number: '1', label: 'Mesa 1', status: 'available');
    final draft = TableOrderDraft.freeTable(table, tables: app.tables, session: app.session, menu: app.menu);
    final gone = MenuProduct.fromJson(_product('sumiu', 'Fora do cardápio', 5));
    final brownie = MenuProduct.fromJson(_product('brownie', 'Brownie', 14));
    draft.cart.addOne(gone);
    expect(draft.blockReason, 'Há item indisponível no pedido. Remova antes de enviar.');
    draft.cart
      ..removeOne('sumiu')
      ..addOne(brownie); // está no cardápio, mas indisponível
    final result = await tester.runAsync(draft.submit);
    expect(result!.ok, isFalse);
    expect(result.error, 'Há item indisponível no pedido. Remova antes de enviar.');
    expect(draft.isNewTable, isTrue);
    expect(server.mutations, isEmpty);
    draft.dispose();
  });

  testWidgets(
    'cardápio: categorias em duas linhas com rolagem lateral, primeira selecionada, subcategorias em seções',
    (tester) async {
      final server = _Server(extraRoots: 6); // 10 categorias raiz
      await _login(tester, server);
      await _openFreeTable(tester);

      expect(find.byType(TableMenuScreen), findsOneWidget);
      expect(find.text('Mesa 1'), findsOneWidget);
      expect(find.text('Nova mesa · Ana'), findsOneWidget);
      expect(find.text('Buscar no cardápio'), findsOneWidget);
      expect(find.text('Conta'), findsNothing);
      expect(find.text('Pedir conta'), findsNothing);

      // Duas linhas: a 1ª e a 2ª categoria na mesma coluna; a 3ª ao lado.
      final c0 = tester.getRect(find.text('BEBIDAS'));
      final c1 = tester.getRect(find.text('PIZZAS'));
      final c2 = tester.getRect(find.text('LANCHES'));
      expect(c1.center.dx, closeTo(c0.center.dx, 0.5));
      expect(c1.top, greaterThan(c0.bottom));
      expect(c2.center.dy, closeTo(c0.center.dy, 0.5));
      expect(c2.left, greaterThan(c0.right));
      // 4 colunas à vista; a 5ª coluna (9ª categoria) só aparece rolando a faixa.
      expect(tester.getRect(find.text('EXTRA 3')).right, lessThan(390));
      expect(tester.getRect(find.text('EXTRA 4')).left, greaterThanOrEqualTo(390 - 14));
      await tester.drag(find.text('LANCHES'), const Offset(-300, 0));
      await tester.pump();
      expect(tester.getRect(find.text('EXTRA 5')).right, lessThanOrEqualTo(390 - 14));
      await tester.drag(find.text('EXTRA 3'), const Offset(300, 0));
      await tester.pump();

      // A primeira categoria já vem aberta: "Bebidas" mostra as subcategorias em seções.
      expect(find.text('SEM ÁLCOOL'), findsOneWidget);
      expect(find.text('CERVEJAS'), findsOneWidget);
      expect(find.text('Guaraná Lata'), findsOneWidget);
      expect(find.text('Long neck'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('CERVEJAS')).dy,
        greaterThan(tester.getTopLeft(find.text('Suco de Laranja')).dy),
      );
      // A lista não rola de lado: o cartão ocupa a largura da tela menos as margens.
      expect(tester.getRect(_productCard('guarana')).left, 14);
      expect(tester.getRect(_productCard('guarana')).right, 390 - 14);

      // Pizza mostra "a partir de"; indisponível não aparece; busca ignora acento e caixa.
      await _category(tester, 'Pizzas');
      expect(find.text('a partir de R\$ 47,00'), findsOneWidget);
      expect(find.text('Pizza · até 2 sabores'), findsOneWidget);
      await _category(tester, 'Porções');
      expect(find.text('Brownie'), findsNothing);
      expect(find.text('Vendido por kg'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'GUARANA');
      await tester.pump();
      expect(find.text('Guaraná Lata'), findsOneWidget);
      expect(find.text('Picanha no quilo'), findsNothing);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets('"+" lança direto e vira contador; 2 latas = 2 toques, sem abrir outra tela e sem tocar no servidor', (
    tester,
  ) async {
    final server = _Server();
    await _login(tester, server);
    await _openFreeTable(tester);

    CountBtn bar() => tester.widget<CountBtn>(find.byType(CountBtn));
    expect(bar().onTap, isNull); // sem itens, "Revisar pedido" fica desabilitado
    expect(find.descendant(of: _productCard('guarana'), matching: find.byType(QtyStepper)), findsNothing);

    final plusAt = tester.getCenter(_plus('guarana'));
    await tester.tap(_plus('guarana'));
    await tester.pump();
    // O botão virou contador na própria linha, com o "+" no mesmo lugar (o
    // segundo toque cai no mesmo ponto) e o cartão ganhou a borda magenta.
    final stepper = find.descendant(of: _productCard('guarana'), matching: find.byType(QtyStepper));
    expect(stepper, findsOneWidget);
    expect(tester.widget<QtyStepper>(stepper).value, '1');
    expect(tester.getCenter(_plus('guarana')), plusAt);
    final card = tester.widget<Container>(
      find.descendant(of: _productCard('guarana'), matching: find.byType(Container)).first,
    );
    expect(((card.decoration! as BoxDecoration).border! as Border).top.color, C.magenta);
    await tester.tap(_plus('guarana'));
    await tester.pump();
    expect(tester.widget<QtyStepper>(stepper).value, '2');
    expect(bar().count, 2);
    expect(bar().total, 14);
    expect(bar().label, 'Revisar pedido');
    expect(bar().onTap, isNotNull);
    expect(find.byType(SheetBody), findsNothing);
    expect(find.byType(TableMenuScreen), findsOneWidget);

    // "−" até zero remove e o "+" simples volta.
    await tester.tap(_minus('guarana'));
    await tester.pump();
    await tester.tap(_minus('guarana'));
    await tester.pump();
    expect(stepper, findsNothing);
    expect(bar().count, 0);

    // Cancelar no cardápio de mesa livre não cria nada no servidor.
    await tester.tap(_plus('guarana'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar o pedido?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TableMenuScreen), findsNothing);
    expect(server.mutationPaths, ['POST /auth/login']);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
    'pizza: janela em abas bloqueia até escolher sabor, desabilita no limite e adiciona com borda e observação',
    (tester) async {
      final server = _Server();
      await _login(tester, server);
      await _openFreeTable(tester);
      await _category(tester, 'Pizzas');

      await tester.tap(_plus('pizza'));
      await tester.pumpAndSettle();
      Btn next() => tester.widget<Btn>(find.widgetWithText(Btn, 'Continuar'));
      expect(find.text('Sabores'), findsOneWidget);
      expect(find.text('Borda'), findsOneWidget);
      expect(find.text('Resumo'), findsOneWidget);
      expect(find.text('ESCOLHA ATÉ 2 SABORES'), findsOneWidget);
      expect(find.text('OBRIGATÓRIO'), findsOneWidget);
      expect(find.text('Escolha ao menos 1 sabor'), findsOneWidget);
      expect(next().onTap, isNull);
      // Sem sabor, as outras abas não abrem.
      await tester.tap(find.text('Resumo'));
      await tester.pump();
      expect(find.text('ESCOLHA ATÉ 2 SABORES'), findsOneWidget);

      await tester.tap(find.text('Calabresa'));
      await tester.pump();
      expect(find.text('Escolha ao menos 1 sabor'), findsNothing);
      expect(next().onTap, isNotNull);
      await tester.tap(find.text('Portuguesa'));
      await tester.pump();
      // Contador verde na aba e total pelo maior sabor.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('R\$ 56,00'), findsNWidgets(2)); // preço do sabor e total do item
      // No limite, o terceiro sabor não entra.
      await tester.tap(find.text('Mussarela'));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(find.text('ESCOLHA ATÉ 1'), findsOneWidget);
      await tester.tap(find.text('Catupiry'));
      await tester.pump();
      expect(find.text('R\$ 66,00'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(find.text('Calabresa / Portuguesa'), findsOneWidget);
      expect(find.text('Catupiry'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'bem assada');
      await tester.tap(find.widgetWithText(Btn, 'Adicionar'));
      await tester.pumpAndSettle();

      // De volta ao cardápio: a pizza conta 1 e o total é o do item montado.
      final bar = tester.widget<CountBtn>(find.byType(CountBtn));
      expect(bar.count, 1);
      expect(bar.total, 66);
      expect(find.byType(SheetBody), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets(
    'mesa livre só abre no servidor ao enviar (pessoas, cliente, comandas e depois o pedido); reenvio após falha não abre de novo',
    (tester) async {
      final server = _Server()..failOrders = 1;
      await _login(tester, server);
      await _openFreeTable(tester);

      // 2 latas pelo "+" e um suco com observação pelo nome.
      await tester.tap(_plus('guarana'));
      await tester.pump();
      await tester.tap(_plus('guarana'));
      await tester.pump();
      await tester.tap(find.text('Suco de Laranja'));
      await tester.pumpAndSettle();
      expect(find.text('OBSERVAÇÕES (OPCIONAL)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'sem gelo');
      await tester.tap(find.text('Adicionar · R\$ 12,00'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CountBtn));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Revisar pedido'), findsOneWidget);
      expect(find.text('Mesa 1 · Ana'), findsOneWidget);
      expect(find.text('NOVOS · AINDA NÃO ENVIADOS'), findsOneWidget);
      expect(find.text('3 ITENS'), findsOneWidget);
      expect(find.text('sem gelo'), findsOneWidget);
      // Até aqui o servidor não recebeu nada além do login.
      expect(server.mutationPaths, ['POST /auth/login']);

      // Pessoas (−/+), cliente e comandas: os campos do antigo "Abrir mesa".
      final people = find.byType(QtyStepper).first;
      await tester.tap(find.descendant(of: people, matching: find.byIcon(Icons.add)));
      await tester.pump();
      await tester.tap(find.descendant(of: people, matching: find.byIcon(Icons.add)));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Carlos');
      await tester.tap(find.text('Com comandas'));
      await tester.pump();
      for (final label in ['A', 'B']) {
        await tester.enterText(find.byType(TextField).at(1), label);
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Adicionar comanda'));
        await tester.pump();
      }
      // Com duas comandas, enviar exige escolher em qual lançar.
      await tester.tap(find.byType(CountBtn));
      await tester.pump();
      expect(find.text('Selecione a comanda para enviar o pedido.'), findsOneWidget);
      expect(server.mutationPaths, ['POST /auth/login']);
      await tester.tap(find.text('B'));
      await tester.pump();

      // 1ª tentativa: a mesa abre, o pedido falha.
      await tester.tap(find.byType(CountBtn));
      await _settle(tester);
      expect(find.textContaining('Sem resposta do servidor'), findsOneWidget);
      expect(find.text('Pedido na cozinha!'), findsNothing);
      expect(server.mutationPaths, ['POST /auth/login', 'POST /tables/t1/sessions', 'POST /sessions/s-new/orders']);
      final open = server.mutations.elementAt(1);
      expect(open.body, {
        'guest_count': 2,
        'customer_name': 'Carlos',
        'comandas': ['A', 'B'],
      });
      final first = server.mutations.elementAt(2);
      expect(first.body['session_comanda_id'], 'cmd-B');

      // 2ª tentativa: só o pedido, com a MESMA chave de idempotência.
      await tester.tap(find.byType(CountBtn));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(server.mutationPaths, [
        'POST /auth/login',
        'POST /tables/t1/sessions',
        'POST /sessions/s-new/orders',
        'POST /sessions/s-new/orders',
      ]);
      final second = server.mutations.elementAt(3);
      expect(second.key, isNotNull);
      expect(second.key, first.key);
      expect(second.body['session_comanda_id'], 'cmd-B');
      expect(second.body['items'], [
        {'product_id': 'guarana', 'quantity': 2},
        {'product_id': 'suco', 'quantity': 1, 'notes': 'sem gelo'},
      ]);

      expect(find.text('Pedido na cozinha!'), findsOneWidget);
      expect(find.text('3 itens da mesa 1'), findsOneWidget);
      expect(find.text('Voltar às mesas'), findsOneWidget);
      await tester.tap(find.text('Ficar na mesa 1'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byType(TableMenuScreen), findsNothing);
      expect(tester.widget<SessionScreen>(find.byType(SessionScreen)).sessionId, 's-new');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets(
    'mesa já aberta: "+ Itens" leva ao cardápio com "Conta"; a revisão mostra os já lançados e avisa quando a produção não recebe',
    (tester) async {
      final server = _Server()..kitchenSent = false;
      await _login(tester, server);
      await tester.tap(_tableCard('2'));
      await _settle(tester);
      expect(find.byType(SessionScreen), findsOneWidget);

      await tester.tap(find.text('+ Itens'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(TableMenuScreen), findsOneWidget);
      expect(find.text('Jefferson · 3 pessoas'), findsOneWidget);
      expect(find.text('Conta'), findsOneWidget);

      await tester.tap(_plus('guarana'));
      await tester.pump();
      await tester.tap(find.byType(CountBtn));
      await tester.pumpAndSettle();
      // Mesa aberta: pessoas só leitura, sem "Comandas", com os itens já lançados e o status de hoje.
      expect(find.text('Pessoas na mesa'), findsOneWidget);
      expect(find.text('Comandas'), findsNothing);
      expect(find.text('JÁ LANÇADOS NESTA MESA'), findsOneWidget);
      expect(find.text('2x Long neck'), findsOneWidget);
      expect(find.text('aguardando'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Jefferson');

      await tester.tap(find.byType(CountBtn));
      await _settle(tester);
      await tester.pumpAndSettle();
      // Mesa aberta não é aberta de novo: só o pedido vai.
      expect(server.mutationPaths, ['POST /auth/login', 'POST /sessions/sess2/orders']);
      expect(find.text('Pedido gravado'), findsOneWidget);
      expect(find.text('Pedido na cozinha!'), findsNothing);
      expect(find.text(kitchenNotSentNotice), findsOneWidget);
      expect(find.text('1 item da mesa 2'), findsOneWidget);

      await tester.tap(find.text('Voltar às mesas'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SessionScreen), findsNothing);
      expect(find.byType(TableCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets(
    'balcão: mesmo cardápio com "Ver venda", tela "Venda de balcão" com −/+ e "Receber" abrindo a tela "Receber venda"',
    (tester) async {
      final server = _Server();
      await _login(tester, server);
      await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Balcão')));
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CounterScreen), findsOneWidget);
      expect(find.byType(MenuScreen), findsOneWidget);
      expect(find.text('Balcão'), findsOneWidget);
      expect(find.text('Venda de balcão · Bar do Zé'), findsOneWidget);
      expect(tester.widget<CountBtn>(find.byType(CountBtn)).label, 'Ver venda');
      expect(tester.widget<CountBtn>(find.byType(CountBtn)).onTap, isNull);

      await tester.tap(_plus('guarana'));
      await tester.pump();
      await tester.tap(_plus('guarana'));
      await tester.pump();
      await tester.tap(find.byType(CountBtn));
      await tester.pumpAndSettle();
      expect(find.byType(CounterSaleScreen), findsOneWidget);
      expect(find.text('Venda de balcão'), findsOneWidget);
      expect(find.text('Bar do Zé · Ana'), findsOneWidget);
      expect(find.text('ITENS DA VENDA'), findsOneWidget);
      expect(find.text('2 ITENS'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      final receive = tester.widget<CountBtn>(find.byType(CountBtn));
      expect(receive.label, 'Receber');
      expect(receive.total, 14);
      expect(find.widgetWithText(Btn, '+ Itens'), findsOneWidget);

      // "Receber" leva à TELA "Receber venda" (não é mais uma janela).
      await tester.tap(find.byType(CountBtn));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveScreen), findsOneWidget);
      expect(find.text('Receber venda'), findsOneWidget);
      expect(find.text('Valor restante'), findsOneWidget);
      await tester.tap(find.widgetWithText(Btn, 'Receber R\$ 14,00 em Dinheiro'));
      await _settle(tester);
      await tester.pumpAndSettle();
      final checkout = server.mutations.last;
      expect(checkout.path, '/counter/checkout');
      expect(checkout.body['items'], [
        {'product_id': 'guarana', 'quantity': 2},
      ]);
      expect(checkout.body['payments'], [
        {'method': 'cash', 'amount': 14.0},
      ]);
      // "Venda recebida" e, dela, uma nova venda no cardápio do balcão.
      expect(find.text('Venda recebida!'), findsOneWidget);
      expect(find.text('Venda #101'), findsOneWidget);
      await tester.tap(find.widgetWithText(Btn, 'Nova venda de balcão'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveScreen), findsNothing);
      expect(find.byType(CounterSaleScreen), findsNothing);
      expect(find.byType(MenuScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets('balcão desabilitado na loja mostra o aviso de sempre', (tester) async {
    final server = _Server()..counterEnabled = false;
    await _login(tester, server);
    await tester.tap(find.descendant(of: find.byType(MainTabBar), matching: find.text('Balcão')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('A venda de balcão pelo app não está habilitada para esta loja.'), findsOneWidget);
    expect(find.text('Peça ao administrador para ativar em Configurações da loja → Mesas.'), findsOneWidget);
    expect(find.byType(MenuScreen), findsNothing);
    await _unmount(tester);
  });
}
