import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobizweb_pos/core/addon_rules.dart';
import 'package:mobizweb_pos/models/models.dart';
import 'package:mobizweb_pos/print/receipt.dart';
import 'package:mobizweb_pos/print/render.dart';

/// Payload no formato de `GET /sessions/{id}/receipt`
/// (SessionReceiptPayloadBuilder do Mobizweb).
const _receipt = <String, dynamic>{
  'store': {'name': 'Bar do Zé', 'document': '12.345.678/0001-90', 'phone': '(11) 4000-1234', 'address_line': 'Rua A, 10'},
  'table_label': 'MESA 12',
  'waiter': 'Ana',
  'customer_name': 'João',
  'opened_at': '2026-11-13T15:00:00Z',
  'items': [
    {
      'rows': [
        {'qty_label': '2', 'qty': 2.0, 'name': 'Coca-Cola', 'unit': 6.0, 'total': 12.0},
      ],
    },
    {
      'rows': [
        {'qty_label': '1', 'qty': 1.0, 'name': 'X-Burger', 'unit': 22.0, 'total': 22.0},
        {'qty_label': '1', 'qty': 1.0, 'name': 'Bacon', 'unit': 4.0, 'total': 4.0},
      ],
      'paid_label': 'PAGO',
    },
  ],
  'subtotal': 38.0,
  'couvert': 10.0,
  'discount': 5.0,
  'addition': 0.0,
  'service_fee': 3.8,
  'service_fee_percentage': 10.0,
  'total': 46.8,
  'paid': 20.0,
  'remaining': 26.8,
  'payments': [
    {'label': 'Dinheiro', 'amount': 20.0, 'change': 5.0},
  ],
  'comanda_labels': ['101'],
};

List<String> _texts(List<PLine> lines) => [
  for (final l in lines)
    if (l is PText) l.text else if (l is PFit) l.text else if (l is PRow) '${l.left} | ${l.right}',
];

void main() {
  group('conta da mesa', () {
    final lines = billReceipt(_receipt, guestCount: 2);
    final texts = _texts(lines);

    test('cabeçalho da loja e identificação da mesa', () {
      expect(texts.first, 'Bar do Zé');
      expect(texts, contains('MESA 12'));
      expect(texts, contains('Comandas: 101'));
      expect(texts, contains('Cliente: João'));
      expect(texts, contains('Atendente: Ana'));
    });

    test('itens, adicionais recuados e marca de pago', () {
      expect(texts, contains('2x Coca-Cola | R\$ 12,00'));
      expect(texts, contains('1x X-Burger | R\$ 22,00'));
      expect(texts, contains('  + Bacon | R\$ 4,00'));
      expect(texts, contains('  [PAGO]'));
    });

    test('totais vêm do servidor, sem recalcular', () {
      expect(texts, contains('Subtotal | R\$ 38,00'));
      expect(texts, contains('Couvert | R\$ 10,00'));
      expect(texts, contains('Desconto | - R\$ 5,00'));
      expect(texts, contains('Taxa de serviço (10%) | R\$ 3,80'));
      expect(texts, contains('TOTAL | R\$ 46,80'));
      expect(texts, contains('Dinheiro | R\$ 20,00'));
      expect(texts, contains('  Troco | R\$ 5,00'));
      expect(texts, contains('RESTANTE | R\$ 26,80'));
      expect(texts, contains('Por pessoa (2) | R\$ 23,40'));
      expect(texts, contains('NÃO É DOCUMENTO FISCAL'));
    });

    test('conta sem pagamento não mostra "Pago/Restante"', () {
      final t = _texts(billReceipt({..._receipt, 'paid': 0.0, 'payments': <dynamic>[]}));
      expect(t.any((x) => x.startsWith('RESTANTE')), isFalse);
    });

    test('payload vazio não quebra', () {
      expect(() => billReceipt(const {}), returnsNormally);
    });
  });

  group('via do pedido', () {
    final burger = MenuProduct(
      id: 'p1',
      name: 'X-Burger',
      price: 22,
      addonGroups: const [
        AddonGroup(
          id: 'g1',
          name: 'Adicionais',
          items: [AddonItem(id: 'a1', name: 'Bacon', price: 4), AddonItem(id: 'a2', name: 'Ovo', price: 2.5)],
        ),
      ],
    );
    final picanha = const MenuProduct(id: 'p2', name: 'Picanha', price: 189.9, allowFractionalQty: true, unitOfMeasure: 'kg');

    final lines = orderTicket(
      tableLabel: 'MESA 5',
      comandaLabel: 'Maria',
      operator: 'Ana',
      when: DateTime(2026, 11, 13, 20, 5),
      items: [
        CartItem(
          localId: '1',
          product: burger,
          quantity: 2,
          notes: 'sem cebola',
          addons: const [AddonChoice('a1', 2), AddonChoice('a2', 1)],
          unitPrice: 32.5,
        ),
        CartItem(localId: '2', product: picanha, quantity: 0.35, unitPrice: 189.9),
      ],
    );
    final texts = _texts(lines);

    test('mostra mesa, comanda, hora e operador', () {
      expect(texts, containsAll(['PEDIDO', 'MESA 5', 'COMANDA Maria', '13/11/2026 20:05 · Ana']));
    });

    test('itens com adicionais, observação e peso', () {
      expect(texts, contains('2x X-Burger'));
      expect(texts, contains('   + 2× Bacon, Ovo'));
      expect(texts, contains('   OBS: sem cebola'));
      expect(texts, contains('0,35 kg Picanha'));
    });
  });

  group('modo texto da impressora', () {
    test('linha de duas colunas é preenchida até a largura da bobina', () {
      final out = toStoneText(const [PRow('TOTAL', 'R\$ 10,00')]);
      expect(out.single.content!.length, textColumns(PSize.medium));
      expect(out.single.content, startsWith('TOTAL'));
      expect(out.single.content, endsWith('R\$ 10,00'));
    });

    test('descrição longa quebra em duas linhas (valor à direita)', () {
      final out = toStoneText(const [PRow('1x Hambúrguer artesanal duplo com cheddar', 'R\$ 45,00')]);
      expect(out, hasLength(2));
      expect(out[1].align, 'right');
    });

    test('texto leva alinhamento e tamanho da documentação', () {
      final out = toStoneText(const [PText('MESA 1', align: PAlign.center, size: PSize.big)]);
      expect(out.single.toJson(), {'type': 'text', 'content': 'MESA 1', 'align': 'center', 'size': 'big'});
    });
  });

  group('regras de adicional', () {
    const required = AddonGroup(id: 'g', name: 'Ponto', min: 1, max: 1, isRequiredFlag: true);
    const optional = AddonGroup(id: 'o', name: 'Extras', min: 1, max: 2, isRequiredFlag: false);
    const legacy = AddonGroup(id: 'l', name: 'Antigo', min: 1);
    const repeat = AddonGroup(id: 'r', name: 'Repete', max: 3, allowRepeat: true);

    test('mínimo só é exigido em grupo obrigatório', () {
      expect(addonsSatisfied([required], {}), isFalse);
      expect(addonsSatisfied([required], {'g': 1}), isTrue);
      expect(addonsSatisfied([optional], {}), isTrue);
    });

    test('cardápio antigo (sem is_required) usa mínimo > 0', () {
      expect(isGroupRequired(legacy), isTrue);
    });

    test('máximo 0 = sem limite', () {
      expect(hasRoom(const AddonGroup(id: 'x', name: 'x'), 50), isTrue);
      expect(hasRoom(optional, 2), isFalse);
    });

    test('limite por adicional', () {
      expect(itemLimit(required, const AddonItem(id: 'a', name: 'a')), 1);
      expect(itemLimit(required, const AddonItem(id: 'a', name: 'a', maxQuantity: 3)), 3);
      expect(itemLimit(repeat, const AddonItem(id: 'a', name: 'a')), 3);
      expect(itemLimit(const AddonGroup(id: 'x', name: 'x', allowRepeat: true), const AddonItem(id: 'a', name: 'a')), repeatCap);
      expect(itemLimit(required, const AddonItem(id: 'a', name: 'a', itemLimit: 5)), 5);
    });

    test('rótulo do grupo', () {
      expect(groupLabel(required), 'Obrigatório · Escolha até 1');
      expect(groupLabel(const AddonGroup(id: 'x', name: 'x')), '');
    });

    test('preço da pizza: maior sabor ou média', () {
      MenuProduct pizza(String rule) => MenuProduct(
        id: 'pz',
        name: 'Pizza',
        type: 'pizza',
        pizza: PizzaConfig(
          maxFlavors: 2,
          pricingRule: rule,
          groupName: 'Sabores',
          flavors: const [FlavorItem(id: 'a', name: 'A', price: 40), FlavorItem(id: 'b', name: 'B', price: 60)],
        ),
      );
      expect(pizzaPrice(pizza('highest'), {'a', 'b'}), 60);
      expect(pizzaPrice(pizza('average'), {'a', 'b'}), 50);
      expect(listPrice(pizza('highest')), (from: true, value: 40.0));
    });
  });

  group('leitura tolerante do JSON da API', () {
    test('dinheiro como string decimal (couvert de comanda) e campos ausentes', () {
      final c = Comanda.fromJson({
        'id': 'c1',
        'label': '101',
        'status': 'open',
        'total': 33,
        'couvert': {'amount': '10.0000', 'persons': 2, 'total': '20.0000'},
      });
      expect(c.couvert!.total, 20);
      expect(c.serviceFee, 0);
      expect(c.hasPayments, isFalse);
    });

    test('sessão sem `bill` nem `transfer_targets` (servidor antigo)', () {
      final s = SessionDetail.fromJson({
        'id': 's1',
        'status': 'open',
        'table': {'id': 't1', 'number': 12, 'label': null},
        'items': [
          {'id': 'i1', 'product_name': 'Suco', 'quantity': '1', 'unit_price': '9.50', 'status': 'pending', 'selected_flavors': ['A', {'id': 'x', 'name': 'B'}]},
        ],
        'other_open_sessions': [
          {'id': 's2', 'table_number': 3},
        ],
      });
      expect(s.title, '12');
      expect(s.bill.total, 0);
      expect(s.items.single.unitPrice, 9.5);
      expect(s.items.single.flavorsLabel, 'A / B');
      expect(s.transferTargets.single.label, 'Mesa 3');
    });

    test('mesa tipo C é comanda', () {
      expect(DiningTable.fromJson({'id': 't', 'number': '101', 'type': 'C', 'status': 'available'}).isComanda, isTrue);
    });

    test('caixa fechado não conta como caixa aberto', () {
      final ctx = CashContext.fromJson({
        'enabled': true,
        'session': {'id': 'c', 'status': 'closed'},
      });
      expect(ctx.session, isNull);
    });
  });

  group('fichas da venda de balcão', () {
    const lata = MenuProduct(id: 'p1', name: 'Refrigerante lata', price: 6);
    const picanha = MenuProduct(id: 'p2', name: 'Picanha', price: 189.9, unitOfMeasure: 'kg', allowFractionalQty: true);
    const cerveja = MenuProduct(id: 'p3', name: 'Cerveja', price: 12, code: '7891');
    final lines = counterTickets(
      number: 100029,
      when: DateTime(2026, 11, 14, 20, 32),
      items: [
        CartItem(localId: '1', product: lata, quantity: 2, unitPrice: 6),
        CartItem(localId: '2', product: picanha, quantity: 0.35, unitPrice: 189.9),
        CartItem(localId: '3', product: cerveja, quantity: 1, notes: 'bem gelada', unitPrice: 12),
      ],
    );

    test('uma ficha por unidade paga; item por peso sai em uma ficha só', () {
      expect(lines.whereType<PCut>().length, 4);
      expect(lines.whereType<PBarcode>().length, 4);
      final names = lines.whereType<PFit>().map((t) => t.text).toList();
      expect(names, ['REFRIGERANTE LATA', 'REFRIGERANTE LATA', 'PICANHA', 'CERVEJA']);
      expect(_texts(lines), contains('0,35 kg'));
    });

    test('cada ficha traz número da venda, data e hora, produto em destaque e código de barras', () {
      final first = lines.takeWhile((l) => l is! PCut).toList();
      final texts = _texts(first);
      expect(texts, containsAllInOrder(['VENDA Nº 100029', '14/11/2026 - 20:32', 'REFRIGERANTE LATA', '100029001']));
      // O nome do produto: em destaque, numa linha só.
      final name = first.whereType<PFit>().single;
      expect((name.text, name.bold), ('REFRIGERANTE LATA', true));
      final stamp = first.whereType<PText>().firstWhere((t) => t.text == '14/11/2026 - 20:32');
      expect(stamp.size, PSize.small);
      expect(lines.last, isA<PGap>());
    });

    test('código de barras: número da venda + código do produto (SKU, ou posição do item)', () {
      final codes = lines.whereType<PBarcode>().map((b) => b.data).toList();
      expect(codes, ['100029001', '100029001', '100029002', '1000297891']);
      expect(_texts(lines), contains('OBS: bem gelada'));
    });

    test('venda sem itens não imprime nada', () {
      expect(counterTickets(number: 1, items: const []), isEmpty);
    });

    test('modo texto: código de barras vai como imagem e o picote como linha', () {
      final out = toStoneText(lines, barcodes: const ['AAA', null, 'CCC', 'DDD']);
      expect(out.where((p) => p.type == 'image').map((p) => p.imageBase64), ['AAA', 'CCC', 'DDD']);
      expect(out.where((p) => p.type == 'line' && p.content!.startsWith('- -')).length, 4);
      // Nome numa linha só: 17 letras não cabem no `big`, descem para `medium`.
      final name = out.firstWhere((p) => p.content == 'REFRIGERANTE LATA');
      expect((name.size, name.align), ('medium', 'center'));
      expect(out.firstWhere((p) => p.content == 'CERVEJA').size, 'big');
    });

    test('nome do produto sempre em uma linha: diminui a letra e, no limite, corta', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      int height(List<int> png) => (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      Future<int> nameHeight(String name) async => height((await renderReceiptPng([PFit(name)])).single);

      // A linha nunca passa da altura de UMA linha no tamanho máximo (40 × 1,25).
      for (final name in ['CERVEJA', 'REFRIGERANTE LATA', 'HAMBÚRGUER ARTESANAL DUPLO COM CHEDDAR E BACON']) {
        expect(await nameHeight(name), lessThanOrEqualTo(50), reason: name);
      }
      // Nome curto usa a letra maior; nome longo, uma menor.
      expect(await nameHeight('REFRIGERANTE LATA DE 350 ML'), lessThan(await nameHeight('CERVEJA')));

      final long = toStoneText(const [PFit('HAMBÚRGUER ARTESANAL DUPLO COM CHEDDAR E BACON ESPECIAL')]).single;
      expect(long.size, 'small');
      expect(long.content!.length, 48);
      expect(long.content, endsWith('...'));
    });

    test('imagem: nenhuma ficha é partida entre duas imagens', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      List<PLine> tickets(double n) => counterTickets(
        number: 100029,
        items: [CartItem(localId: '1', product: lata, quantity: n, unitPrice: 6)],
      );
      // Altura do PNG (IHDR, bytes 20 a 23).
      int height(List<int> png) => (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];

      final one = (await renderReceiptPng(tickets(1), maxHeight: 4000)).single;
      final all = (await renderReceiptPng(tickets(6), maxHeight: 4000)).single;
      final ticket = (height(all) - height(one)) ~/ 5;

      // Limite em que cabem duas fichas e meia: saem duas INTEIRAS por imagem.
      final pages = await renderReceiptPng(tickets(6), maxHeight: ticket * 2.5);
      expect(pages.length, 3);
      expect(pages.map(height).toSet().length, lessThanOrEqualTo(2));
      expect(height(pages.first), ticket * 2);
      // O avanço de papel do fim acompanha a última ficha.
      expect(height(pages.last), ticket * 2 + (height(one) - ticket));

      expect(await renderBarcodesBase64(tickets(6)), hasLength(6));
    });
  });

  group('comprovante de balcão com preço recalculado pelo servidor', () {
    const lata = MenuProduct(id: 'p1', name: 'Refrigerante lata', price: 6);
    final items = [CartItem(localId: '1', product: lata, quantity: 10, unitPrice: 6)];

    test('mostra subtotal e desconto quando o servidor grava por menos', () {
      final rows = counterReceipt(
        storeName: 'Bar',
        items: items,
        payments: const [(label: 'Dinheiro', amount: 60)],
        total: 54,
        change: 6,
        itemsTotal: 60,
      ).whereType<PRow>().map((r) => '${r.left}|${r.right}').toList();
      expect(rows, containsAllInOrder(['Subtotal|R\$ 60,00', 'Desconto|- R\$ 6,00', 'TOTAL|R\$ 54,00', 'Troco|R\$ 6,00']));
    });

    test('sem diferença, o comprovante continua igual', () {
      final rows = counterReceipt(
        storeName: 'Bar',
        items: items,
        payments: const [(label: 'Dinheiro', amount: 60)],
        total: 60,
        itemsTotal: 60,
      ).whereType<PRow>().map((r) => r.left).toList();
      expect(rows, isNot(contains('Subtotal')));
      expect(rows, isNot(contains('Desconto')));
    });
  });

  group('DANFE NFC-e na maquininha', () {
    const note = FiscalNote(
      number: 1201,
      series: 1,
      lines: [
        DanfeLine('BAR DO ZE LTDA', center: true, bold: true),
        DanfeLine('--------------------------------'),
        DanfeLine('VALOR A PAGAR R\$          14,00', bold: true),
        DanfeLine('https://sefaz/qr?p=3526', center: true, qr: true),
        DanfeLine('Chave de acesso muito comprida que passa das trinta e duas colunas'),
      ],
    );
    final lines = danfeReceipt(note);

    test('modo texto: linhas no tamanho de 32 colunas e o QR como imagem', () {
      final out = toStoneText(lines, qrs: {'https://sefaz/qr?p=3526': Uint8List.fromList([1, 2, 3])});
      expect(out.first.content, 'BAR DO ZE LTDA');
      expect((out.first.align, out.first.size), ('center', 'medium'));
      expect(out[2].content, 'VALOR A PAGAR R\$          14,00');
      expect(out.where((p) => p.type == 'image').single.imageBase64, 'AQID');
      // Sem a imagem do QR (prévia, testes) a linha simplesmente não sai.
      expect(toStoneText(lines).where((p) => p.type == 'image'), isEmpty);
    });

    test('imagem: cada linha ocupa uma linha só, mesmo a que passa da largura', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      int height(List<int> png) => (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      final one = height((await renderReceiptPng(const [PMono('TOTAL')])).single);
      final long = height(
        (await renderReceiptPng(const [
          PMono('Chave de acesso muito comprida que passa das trinta e duas colunas'),
        ])).single,
      );
      // Linha comprida é encolhida (fica mais baixa), nunca vira duas.
      expect(long, lessThanOrEqualTo(one));
      // O documento inteiro renderiza sem a imagem do QR.
      expect(await renderReceiptPng(lines, maxHeight: 4000), hasLength(1));
    });
  });
}
