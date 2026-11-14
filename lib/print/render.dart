import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/config.dart';
import '../stone/stone_deeplink.dart';
import 'barcode.dart';
import 'receipt.dart';

/// Tamanhos de fonte na bobina de 58 mm (384 pontos).
double _fontSize(PSize s) => switch (s) {
  PSize.small => 20,
  PSize.medium => 24,
  PSize.big => 32,
};

/// Colunas por linha no modo texto. A Stone não documenta esse número; estes
/// valores são os usuais de térmica 58 mm (fonte A = 32, fonte B = 48).
int textColumns(PSize s) => s == PSize.small ? 48 : 32;

/// Quantas letras cabem em uma linha no tamanho `big` do modo texto (largura
/// dobrada). Valor conservador: acima disso o nome desce para `medium`.
const bigTextColumns = 16;

// ── Modo texto ───────────────────────────────────────────────────────────────

/// Converte para itens `text`/`line` do deeplink. Mais leve que imagem, mas o
/// alinhamento das colunas depende da fonte do terminal.
///
/// Código de barras não existe em texto: [barcodes] traz o PNG (base64) de
/// cada [PBarcode], na ordem em que aparecem (ver [renderBarcodesBase64]).
/// Sem ele, o número já sai escrito na linha seguinte do documento.
List<StonePrintable> toStoneText(List<PLine> lines, {List<String?> barcodes = const []}) {
  final out = <StonePrintable>[];
  var barcode = 0;
  for (final l in lines) {
    switch (l) {
      case PText():
        out.add(StonePrintable.text(l.text, align: l.align.name, size: l.size.name));
      case PRow():
        final cols = textColumns(l.size);
        final gap = cols - l.left.length - l.right.length;
        if (gap >= 1) {
          out.add(StonePrintable.text('${l.left}${' ' * gap}${l.right}', size: l.size.name));
        } else {
          out.add(StonePrintable.text(l.left, size: l.size.name));
          if (l.right.isNotEmpty) out.add(StonePrintable.text(l.right, align: 'right', size: l.size.name));
        }
      case PDivider():
        out.add(StonePrintable.line('-' * 32));
      case PGap():
        out.add(const StonePrintable.line(' '));
      case PFit():
        // Uma linha só: o maior tamanho da Stone em que o texto cabe.
        final size = l.text.length <= bigTextColumns
            ? PSize.big
            : (l.text.length <= textColumns(PSize.medium) ? PSize.medium : PSize.small);
        final max = textColumns(size);
        final text = l.text.length <= max ? l.text : '${l.text.substring(0, max - 3)}...';
        out.add(StonePrintable.text(text, align: 'center', size: size.name));
      case PBarcode():
        final image = barcode < barcodes.length ? barcodes[barcode] : null;
        barcode++;
        if (image != null) out.add(StonePrintable.image(image));
      case PCut():
        out
          ..add(const StonePrintable.line(' '))
          ..add(StonePrintable.line('- ' * 16))
          ..add(const StonePrintable.line(' '));
    }
  }
  return out;
}

/// PNG (base64) de cada [PBarcode] do documento, na ordem; `null` quando o
/// código não cabe no papel. Usado pela impressão em modo texto.
Future<List<String?>> renderBarcodesBase64(List<PLine> lines, {int width = Config.paperWidthPx}) async {
  final out = <String?>[];
  for (final l in lines.whereType<PBarcode>()) {
    if (code128ModuleWidth(l.data, width) == 0) {
      out.add(null);
      continue;
    }
    final pngs = await renderReceiptPng([l], width: width);
    out.add(pngs.isEmpty ? null : base64Encode(pngs.first));
  }
  return out;
}

// ── Modo imagem ──────────────────────────────────────────────────────────────

const _ink = ui.Color(0xFF000000);
const _paper = ui.Color(0xFFFFFFFF);

class _Block {
  _Block(this.height, this.paint, {this.cut = false});
  final double height;
  final void Function(ui.Canvas canvas, double y) paint;

  /// Fim de uma via destacável ([PCut]): ponto preferido para trocar de imagem.
  final bool cut;
}

TextPainter _tp(String text, PSize size, bool bold, double maxWidth, [TextAlign align = TextAlign.left]) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: _ink,
        fontSize: _fontSize(size),
        // Traço fino some na térmica: o "normal" já é médio.
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        height: 1.25,
      ),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  );
  tp.layout(minWidth: maxWidth, maxWidth: maxWidth);
  return tp;
}

/// O texto de [PFit] em UMA linha: maior tamanho entre `maxSize` e `minSize`
/// que cabe em [width]; no menor, corta com reticências.
TextPainter _fit(PFit l, double width) {
  TextPainter build(double size, {bool clip = false}) => TextPainter(
    text: TextSpan(
      text: l.text,
      style: TextStyle(
        color: _ink,
        fontSize: size,
        fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500,
        height: 1.25,
      ),
    ),
    maxLines: 1,
    ellipsis: clip ? '…' : null,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: clip ? width : double.infinity);

  for (var size = l.maxSize; size >= l.minSize; size -= 2) {
    final tp = build(size);
    if (tp.width <= width) return tp;
    tp.dispose();
  }
  return build(l.minSize, clip: true);
}

List<_Block> _layout(List<PLine> lines, double width) {
  final blocks = <_Block>[];
  for (final l in lines) {
    switch (l) {
      case PText():
        final align = switch (l.align) {
          PAlign.left => TextAlign.left,
          PAlign.center => TextAlign.center,
          PAlign.right => TextAlign.right,
        };
        final tp = _tp(l.text, l.size, l.bold, width, align);
        blocks.add(_Block(tp.height, (c, y) => tp.paint(c, ui.Offset(0, y))));
      case PRow():
        final right = TextPainter(
          text: TextSpan(
            text: l.right,
            style: TextStyle(
              color: _ink,
              fontSize: _fontSize(l.size),
              fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500,
              height: 1.25,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final leftWidth = (width - right.width - 12).clamp(80.0, width);
        final left = _tp(l.left, l.size, l.bold, leftWidth);
        final h = left.height > right.height ? left.height : right.height;
        blocks.add(
          _Block(h, (c, y) {
            left.paint(c, ui.Offset(0, y));
            right.paint(c, ui.Offset(width - right.width, y));
          }),
        );
      case PDivider():
        blocks.add(
          _Block(14, (c, y) {
            final p = ui.Paint()
              ..color = _ink
              ..strokeWidth = 2;
            for (double x = 0; x < width; x += 10) {
              c.drawLine(ui.Offset(x, y + 7), ui.Offset(x + 6, y + 7), p);
            }
          }),
        );
      case PGap():
        blocks.add(_Block(l.px, (_, _) {}));
      case PFit():
        final tp = _fit(l, width);
        blocks.add(_Block(tp.height, (c, y) => tp.paint(c, ui.Offset((width - tp.width) / 2, y))));
      case PBarcode():
        final modules = code128Modules(l.data);
        final unit = code128ModuleWidth(l.data, width.toInt());
        // Não cabe no papel: o número sai escrito na linha seguinte.
        if (unit == 0) break;
        final left = ((width - modules.length * unit) / 2).floorToDouble();
        blocks.add(
          _Block(l.height, (c, y) {
            final p = ui.Paint()..color = _ink;
            // Barras vizinhas viram um retângulo só (sem fresta entre módulos).
            var i = 0;
            while (i < modules.length) {
              if (!modules[i]) {
                i++;
                continue;
              }
              var j = i;
              while (j < modules.length && modules[j]) {
                j++;
              }
              c.drawRect(ui.Rect.fromLTWH(left + i * unit, y, (j - i) * unit.toDouble(), l.height), p);
              i = j;
            }
          }),
        );
      case PCut():
        // Linha de picote com folga em cima e embaixo para rasgar.
        blocks.add(
          _Block(44, (c, y) {
            final p = ui.Paint()
              ..color = _ink
              ..strokeWidth = 2;
            for (double x = 0; x < width; x += 16) {
              c.drawLine(ui.Offset(x, y + 22), ui.Offset(x + 8, y + 22), p);
            }
          }, cut: true),
        );
    }
  }
  return blocks;
}

/// Divide em imagens de até [maxHeight]. Uma via destacável (o trecho até um
/// [PCut]) nunca é partida no meio quando cabe inteira em uma imagem; o resto
/// quebra entre linhas.
List<List<_Block>> _paginate(List<_Block> blocks, double maxHeight) {
  final groups = <List<_Block>>[];
  var group = <_Block>[];
  for (final b in blocks) {
    group.add(b);
    if (b.cut) {
      groups.add(group);
      group = <_Block>[];
    }
  }
  if (group.isNotEmpty) {
    // O avanço de papel depois da última via acompanha essa via (não vira
    // uma imagem só de papel em branco).
    if (groups.isNotEmpty && group.every((b) => !b.cut)) {
      groups.last.addAll(group);
    } else {
      groups.add(group);
    }
  }

  final pages = <List<_Block>>[];
  var current = <_Block>[];
  var used = 0.0;
  void close() {
    if (current.isNotEmpty) pages.add(current);
    current = <_Block>[];
    used = 0;
  }

  for (final g in groups) {
    final height = g.fold<double>(0, (a, b) => a + b.height);
    final whole = groups.length > 1 && height <= maxHeight;
    if (whole && used + height > maxHeight) close();
    for (final b in g) {
      if (!whole && current.isNotEmpty && used + b.height > maxHeight) close();
      current.add(b);
      used += b.height;
    }
  }
  close();
  return pages;
}

/// Renderiza o documento em PNGs de 384 px de largura, quebrando SEMPRE entre
/// linhas e respeitando [maxHeight] por imagem (terminais antigos recusam
/// imagem alta — a doc da Stone cita 380×595 no APOS A8).
Future<List<Uint8List>> renderReceiptPng(
  List<PLine> lines, {
  int width = Config.paperWidthPx,
  double maxHeight = 560,
}) async {
  final pages = _paginate(_layout(lines, width.toDouble()), maxHeight);

  final out = <Uint8List>[];
  for (final page in pages) {
    final h = page.fold<double>(0, (a, b) => a + b.height).ceil().clamp(1, 100000);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), h.toDouble()), ui.Paint()..color = _paper);
    var y = 0.0;
    for (final b in page) {
      b.paint(canvas, y);
      y += b.height;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes != null) out.add(bytes.buffer.asUint8List());
  }
  return out;
}

/// Agrupa as imagens em chamadas de impressão pequenas. Intent grande trava
/// sem erro (limite do Binder ~1 MB) e a Stone orienta "uma imagem (ou
/// poucas) por chamada, de forma sequencial".
List<List<StonePrintable>> toStoneImageCalls(List<Uint8List> pngs, {int maxBytesPerCall = 180 * 1024}) {
  final calls = <List<StonePrintable>>[];
  var current = <StonePrintable>[];
  var size = 0;
  for (final png in pngs) {
    final b64 = base64Encode(png);
    if (current.isNotEmpty && size + b64.length > maxBytesPerCall) {
      calls.add(current);
      current = <StonePrintable>[];
      size = 0;
    }
    current.add(StonePrintable.image(b64));
    size += b64.length;
  }
  if (current.isNotEmpty) calls.add(current);
  return calls;
}
