import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/native.dart';
import '../../models/models.dart';
import '../../stores/comanda_link.dart';
import '../kit.dart';
import '../table_card.dart';

/// "Ler QR da comanda": o garçom lê o QR do cartão/comanda com a CÂMERA (ou
/// digita o código impresso) e diz a que MESA ele pertence. Daí em diante os
/// pedidos daquela comanda caem naquela mesa. Mesmo fluxo do
/// `ComandaScanModal.vue` do PWA, em dois passos (conferir o código, escolher
/// a mesa).
///
/// A câmera é a do aparelho, aberta pelo lado nativo (`Native.scanQr`, ZXing).
/// Sem câmera, com a permissão negada ou onde o leitor não existe (prévia
/// web), fica o aviso e o garçom segue digitando.
class ComandaLinkSheet extends StatefulWidget {
  const ComandaLinkSheet({super.key});

  @override
  State<ComandaLinkSheet> createState() => _ComandaLinkSheetState();
}

class _ComandaLinkSheetState extends State<ComandaLinkSheet> {
  final _code = TextEditingController();
  ComandaLookup? _found;
  String? _tableId;
  String? _success;
  String? _error;

  /// Aviso sobre a câmera (sem câmera, permissão negada): não é erro de
  /// comanda, por isso fica separado de [_error].
  String? _cameraNote;
  bool _busy = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    if (app.tables.tables.isEmpty) app.tables.fetch();
  }

  /// "Ler com a câmera": abre o leitor do aparelho e, lido o QR, confere o
  /// código no servidor como se tivesse sido digitado.
  Future<void> _scan() async {
    if (_busy || _scanning) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _error = null;
      _cameraNote = null;
    });
    final scan = await app.native.scanQr(prompt: 'Aponte para o QR da comanda');
    if (!mounted) return;
    setState(() => _scanning = false);
    switch (scan.status) {
      case QrScanStatus.read:
        final code = comandaCodeFromQr(scan.text);
        if (code == null) {
          setState(() => _cameraNote = 'Não foi possível ler o QR. Tente de novo ou digite o código da comanda.');
          return;
        }
        _code.text = code;
        await _lookup();
      case QrScanStatus.canceled:
        break;
      case QrScanStatus.noCamera:
        setState(() => _cameraNote = 'Este aparelho não tem câmera. Digite o código da comanda.');
      case QrScanStatus.denied:
        setState(
          () => _cameraNote =
              'A câmera não foi liberada para o app. Libere nos ajustes do aparelho ou digite o código da comanda.',
        );
      case QrScanStatus.unavailable:
        setState(() => _cameraNote = 'Câmera indisponível neste aparelho. Digite o código da comanda.');
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Só MESAS recebem vínculo: comanda não se vincula a comanda.
  List<DiningTable> get _mesas =>
      app.tables.tables.where((t) => !t.isComanda).toList()
        ..sort((a, b) => naturalCompare(tableCardTitle(a), tableCardTitle(b)));

  Future<void> _lookup() async {
    final code = _code.text.trim();
    if (_busy || code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await app.comandaLink.lookup(code);
      if (!mounted) return;
      setState(() {
        if (found.linked) {
          _success = found.tableNumber == null
              ? 'A comanda ${found.label} já está em uma mesa.'
              : 'A comanda ${found.label} já está na mesa ${found.tableNumber}.';
        } else {
          _found = found;
        }
      });
    } on ComandaLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    final tableId = _tableId;
    final found = _found;
    if (_busy || tableId == null || found == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final number = await app.comandaLink.link(_code.text, tableId);
      app.tables.fetch();
      app.notifications.fetch();
      if (!mounted) return;
      setState(
        () => _success = number == null
            ? 'Comanda ${found.label} vinculada.'
            : 'Comanda ${found.label} vinculada à mesa $number.',
      );
    } on ComandaLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success != null) {
      return SheetBody(
        title: 'Ler QR da comanda',
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 22, color: C.greenText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _success!,
                    style: T.body(w: T.semibold, c: C.greenText),
                  ),
                ),
              ],
            ),
          ),
        ],
        footer: Btn('Fechar', kind: BtnKind.navy, onTap: () => Navigator.pop(context)),
      );
    }

    final found = _found;
    if (found == null) {
      return SheetBody(
        title: 'Ler QR da comanda',
        subtitle: 'Aponte a câmera para o QR da comanda ou digite o código impresso nela.',
        children: [
          Btn(
            _scanning ? 'Abrindo a câmera...' : 'Ler com a câmera',
            kind: BtnKind.magenta,
            icon: Icons.qr_code_scanner,
            loading: _scanning,
            onTap: _busy ? null : _scan,
          ),
          if (_cameraNote != null) ...[const SizedBox(height: 10), Note(_cameraNote!, center: false, radius: 12)],
          const SizedBox(height: 16),
          Field(
            label: 'Ou digite o código da comanda',
            controller: _code,
            hint: 'Ex.: 101',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            maxLength: 120,
            large: true,
            action: TextInputAction.done,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          ErrText(_error),
        ],
        footer: BtnRow(
          Btn('Cancelar', kind: BtnKind.secondary, onTap: _busy ? null : () => Navigator.pop(context)),
          Btn(
            _busy ? 'Conferindo...' : 'Continuar',
            kind: BtnKind.navy,
            loading: _busy,
            onTap: _code.text.trim().isEmpty || _scanning ? null : _lookup,
          ),
        ),
      );
    }

    final mesas = _mesas;
    return SheetBody(
      title: 'Comanda ${found.label}',
      subtitle: 'Ainda não está em nenhuma mesa. Escolha a mesa: os próximos pedidos desta comanda entram nela.',
      children: [
        if (mesas.isEmpty)
          Text('Nenhuma mesa disponível nesta loja.', style: T.body(c: C.sub))
        else
          ColGrid(
            cols: 4,
            children: [
              for (final t in mesas)
                Tap(
                  onTap: _busy ? null : () => setState(() => _tableId = t.id),
                  color: _tableId == t.id ? C.navy : C.white,
                  border: BorderSide(color: _tableId == t.id ? C.navy : C.line, width: 1.5),
                  radius: 12,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 46),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          tableCardTitle(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.num(14, c: _tableId == t.id ? C.white : C.ink),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        ErrText(_error),
      ],
      footer: BtnRow(
        Btn(
          'Voltar',
          kind: BtnKind.secondary,
          onTap: _busy
              ? null
              : () => setState(() {
                  _found = null;
                  _tableId = null;
                  _error = null;
                }),
        ),
        Btn(
          _busy ? 'Vinculando...' : 'Vincular à mesa',
          kind: BtnKind.green,
          loading: _busy,
          onTap: _tableId == null ? null : _link,
        ),
      ),
    );
  }
}
