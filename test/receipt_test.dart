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
    if (l is PText) l.text else if (l is PRow) '${l.left} | ${l.right}',
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
}
