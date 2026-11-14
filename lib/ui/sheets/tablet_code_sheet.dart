import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../kit.dart';

/// "Gerar QR do tablet na mesa": gera o código de 6 dígitos da mesa e mostra
/// o QR (o cliente lê com a câmera do tablet) e o código grande, para digitar.
/// Gerar de novo substitui o código anterior. Espelha `TabletCodeModal.vue`
/// do PWA: mesma rota (`POST /sessions/{id}/tablet-code`) e o QR codifica só o
/// código.
///
/// O QR é uma imagem PNG desenhada no lado nativo (`Native.qrPng`, ZXing).
/// Onde o nativo não existe (prévia web, testes) aparece só o código.
class TabletCodeSheet extends StatefulWidget {
  const TabletCodeSheet({super.key});

  @override
  State<TabletCodeSheet> createState() => _TabletCodeSheetState();
}

class _TabletCodeSheetState extends State<TabletCodeSheet> {
  bool _loading = true;
  String? _error;
  String _code = '';
  String? _tableNumber;
  Uint8List? _qr;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await app.session.generateTabletCode();
      final qr = r.code.isEmpty ? null : await app.native.qrPng(r.code, size: 480);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _code = r.code;
        _tableNumber = r.tableNumber;
        _qr = qr;
        if (r.code.isEmpty) _error = 'Não foi possível gerar o código. Tente novamente.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.isNetwork ? e.message : 'Não foi possível gerar o código. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = _tableNumber ?? app.session.session?.tableNumber;
    final qr = _qr;
    return SheetBody(
      title: 'Tablet na mesa${number == null ? '' : ' · $number'}',
      children: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('Gerando código...', textAlign: TextAlign.center, style: T.body(c: C.sub)),
          )
        else if (_error != null) ...[
          Note(_error!, kind: NoteKind.error, radius: 12),
          const SizedBox(height: 12),
          Btn('Tentar de novo', kind: BtnKind.secondary, onTap: _generate),
        ] else ...[
          if (qr != null)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: C.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line, width: 1.5),
                ),
                child: Semantics(
                  label: 'QR do tablet',
                  image: true,
                  child: Image.memory(
                    qr,
                    width: 208,
                    height: 208,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          Semantics(
            label: 'Código ${_code.split('').join(' ')}',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _code,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: T.num(34, c: C.ink, h: 1.2).copyWith(letterSpacing: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              text: 'Peça ao cliente para tocar em ',
              children: [
                TextSpan(text: 'Abrir mesa', style: T.s(12.5, w: T.bold, c: C.ink, h: 1.4)),
                TextSpan(
                  text: qr == null
                      ? ' no tablet e digitar o código. Vale até a mesa fechar.'
                      : ' no tablet e apontar a câmera para o QR, ou digitar o código. Vale até a mesa fechar.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: T.s(12.5, c: C.sub, h: 1.4),
          ),
        ],
      ],
      footer: Btn('Fechar', kind: BtnKind.navy, onTap: () => Navigator.pop(context)),
    );
  }
}
