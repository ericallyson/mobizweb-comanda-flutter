import 'package:flutter_test/flutter_test.dart';
import 'package:mobizweb_pos/core/api.dart';
import 'package:mobizweb_pos/core/format.dart';
import 'package:mobizweb_pos/core/uuid.dart';

void main() {
  group('brl', () {
    test('formata em reais pt-BR', () {
      expect(brl(0), 'R\$ 0,00');
      expect(brl(12.5), 'R\$ 12,50');
      expect(brl(1234.56), 'R\$ 1.234,56');
      expect(brl(1234567.8), 'R\$ 1.234.567,80');
      expect(brl(null), 'R\$ 0,00');
      expect(brl(-3.2), '-R\$ 3,20');
    });

    test('arredonda meio centavo sem erro de ponto flutuante', () {
      expect(brl(19.99), 'R\$ 19,99');
      expect(brl(0.1 + 0.2), 'R\$ 0,30');
    });
  });

  group('centavos para a maquininha', () {
    test('nunca trunca (19,99 → 1999, não 1998)', () {
      expect(toCents(19.99), 1999);
      expect(toCents(0.29), 29);
      expect(toCents(1.15), 115);
      expect(toCents(100), 10000);
      expect(toCents(4.35), 435);
    });
  });

  group('parseDecimal', () {
    test('aceita vírgula, ponto e milhar', () {
      expect(parseDecimal('12,5'), 12.5);
      expect(parseDecimal('12.5'), 12.5);
      expect(parseDecimal('1.234,56'), 1234.56);
      expect(parseDecimal('R\$ 10,00'), 10);
      expect(parseDecimal(''), 0);
      expect(parseDecimal('abc'), 0);
    });
  });

  test('qty mostra inteiro sem casas e peso com vírgula', () {
    expect(qty(2), '2');
    expect(qty(2.0), '2');
    expect(qty(0.35), '0,35');
    expect(qty(1.255), '1,255');
  });

  test('percent', () {
    expect(percent(10), '10');
    expect(percent(12.5), '12,5');
  });

  test('fold ignora acento e caixa', () {
    expect(fold('Açaí COM Pão'), 'acai com pao');
  });

  test('naturalCompare ordena Mesa 2 antes de Mesa 10', () {
    final list = ['10', '2', '1', 'A3', 'A12'];
    list.sort(naturalCompare);
    expect(list, ['1', '2', '10', 'A3', 'A12']);
  });

  test('uuidV7 tem formato e versão corretos e cabe na Idempotency-Key', () {
    final id = uuidV7();
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(id.length, lessThanOrEqualTo(64));
    expect(uuidV7(), isNot(id));
  });

  group('normalizeServerUrl', () {
    const d = 'mobizweb.com.br';
    test('slug vira subdomínio https', () {
      expect(normalizeServerUrl('minhaloja', defaultDomain: d), 'https://minhaloja.mobizweb.com.br');
      expect(normalizeServerUrl('  MinhaLoja ', defaultDomain: d), 'https://minhaloja.mobizweb.com.br');
    });
    test('domínio completo é mantido', () {
      expect(normalizeServerUrl('loja.exemplo.com', defaultDomain: d), 'https://loja.exemplo.com');
      expect(normalizeServerUrl('https://loja.exemplo.com/garcom/login', defaultDomain: d), 'https://loja.exemplo.com');
    });
    test('http explícito (hub local) e porta são respeitados', () {
      expect(normalizeServerUrl('http://192.168.0.10:8080', defaultDomain: d), 'http://192.168.0.10:8080');
    });
    test('vazio continua vazio', () {
      expect(normalizeServerUrl('   ', defaultDomain: d), '');
    });
  });
}
