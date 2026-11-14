import 'package:flutter_test/flutter_test.dart';
import 'package:mobizweb_pos/print/barcode.dart';

void main() {
  group('Code 128', () {
    test('só dígitos em quantidade par: conjunto C, um símbolo a cada dois dígitos', () {
      // Início C (105), "12", verificador (105 + 12×1) mod 103 = 14, parada (106).
      expect(code128Values('12'), [105, 12, 14, 106]);
      expect(code128Values('100029').sublist(0, 4), [105, 10, 0, 29]);
    });

    test('dígitos em quantidade ímpar: o último sai no conjunto B', () {
      // 105, "10", "00", troca para B (100), "2" (50 − 32 = 18), verificador, parada.
      final v = code128Values('10002');
      expect(v.sublist(0, 5), [105, 10, 0, 100, 18]);
      expect(v[5], (105 + 10 * 1 + 0 * 2 + 100 * 3 + 18 * 4) % 103);
      expect(v.last, 106);
    });

    test('texto com letra ou traço: conjunto B inteiro', () {
      // Início B (104), "A" = 33, "-" = 13, "1" = 17.
      final v = code128Values('A-1');
      expect(v.sublist(0, 4), [104, 33, 13, 17]);
      expect(v[4], (104 + 33 * 1 + 13 * 2 + 17 * 3) % 103);
    });

    test('caractere fora do ASCII vira traço e o código continua saindo', () {
      expect(code128Sanitize(' AÇÃO1 '), 'A--O1');
      expect(code128Values('ação'), isNotEmpty);
      expect(code128Values('  '), isEmpty);
    });

    test('cada símbolo tem 11 módulos e a parada 13; começa e termina em barra', () {
      final modules = code128Modules('100029001');
      final symbols = code128Values('100029001').length;
      expect(modules.length, (symbols - 1) * 11 + 13);
      expect(modules.first, isTrue);
      expect(modules.last, isTrue);
    });

    test('largura do módulo: maior possível que caiba no papel com as margens', () {
      // 9 dígitos: 105 + 4 pares + troca + 1 dígito + verificador + parada = 9 símbolos.
      final modules = code128Modules('100029001').length;
      expect(modules, 8 * 11 + 13);
      expect(code128ModuleWidth('100029001', 384), 3);
      expect(code128ModuleWidth('100029001', 384) * (modules + 2 * code128QuietZone), lessThanOrEqualTo(384));
      // Código longo demais para a bobina: não desenha (imprime só o número).
      expect(code128ModuleWidth('VENDA-100029-PRODUTO-COM-CODIGO-MUITO-LONGO', 384), 0);
      expect(code128ModuleWidth('', 384), 0);
    });
  });
}
