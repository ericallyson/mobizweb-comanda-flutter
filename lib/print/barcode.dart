/// Código de barras Code 128 (o das fichas da venda de balcão). Código puro,
/// sem dependência: devolve as barras como lista de módulos para o
/// renderizador desenhar. Testado em `test/barcode_test.dart`.
library;

/// Larguras (barra, espaço, barra, espaço, barra, espaço) de cada um dos 106
/// símbolos do Code 128; o último é o de parada, com sete elementos.
const _patterns = <String>[
  '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213', //
  '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132', //
  '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211', //
  '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313', //
  '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331', //
  '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111', //
  '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214', //
  '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111', //
  '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141', //
  '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141', //
  '114131', '311141', '411131', '211412', '211214', '211232', '2331112',
];

const _startB = 104;
const _startC = 105;
const _codeB = 100;
const _stop = 106;

/// Margem clara de cada lado, em módulos (a norma pede 10).
const code128QuietZone = 10;

bool _isDigits(String s) => s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

/// Texto que cabe no Code 128 B: só ASCII imprimível. O que não cabe (acento,
/// controle) vira `-`, para o código nunca deixar de sair.
String code128Sanitize(String data) =>
    String.fromCharCodes(data.trim().codeUnits.map((c) => (c >= 32 && c <= 126) ? c : 0x2D));

/// Valores dos símbolos (início, dados, verificador e parada).
///
/// Só dígitos: conjunto C, dois dígitos por símbolo (metade da largura); com
/// quantidade ímpar, o último dígito sai no conjunto B. Qualquer outro texto:
/// conjunto B inteiro.
List<int> code128Values(String data) {
  final text = code128Sanitize(data);
  if (text.isEmpty) return const [];
  final values = <int>[];
  if (_isDigits(text) && text.length >= 2) {
    values.add(_startC);
    final pairs = text.length ~/ 2;
    for (var i = 0; i < pairs; i++) {
      values.add(int.parse(text.substring(i * 2, i * 2 + 2)));
    }
    if (text.length.isOdd) {
      values
        ..add(_codeB)
        ..add(text.codeUnitAt(text.length - 1) - 32);
    }
  } else {
    values.add(_startB);
    for (final c in text.codeUnits) {
      values.add(c - 32);
    }
  }
  var sum = values.first;
  for (var i = 1; i < values.length; i++) {
    sum += values[i] * i;
  }
  values
    ..add(sum % 103)
    ..add(_stop);
  return values;
}

/// As barras, módulo a módulo (`true` = preto), SEM as margens claras.
/// Lista vazia quando não há o que codificar.
List<bool> code128Modules(String data) {
  final out = <bool>[];
  for (final v in code128Values(data)) {
    var bar = true;
    for (final w in _patterns[v].codeUnits) {
      for (var i = 0; i < w - 0x30; i++) {
        out.add(bar);
      }
      bar = !bar;
    }
  }
  return out;
}

/// Largura de cada módulo, em pontos, para o código caber em [width] com as
/// margens. `0` = não cabe (o documento imprime só o número).
int code128ModuleWidth(String data, int width, {int max = 3}) {
  final modules = code128Modules(data).length;
  if (modules == 0) return 0;
  final fit = width ~/ (modules + 2 * code128QuietZone);
  return fit > max ? max : fit;
}
