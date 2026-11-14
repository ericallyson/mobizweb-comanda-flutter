import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../kit.dart';

/// Pix online: gera o QR no servidor, mostra, consulta a cada 4 s e registra
/// o pagamento quando o provedor confirma. Espelha `PixReceiveModal.vue`.
/// Fecha com `true` quando o pagamento foi registrado.
class PixSheet extends StatefulWidget {
  const PixSheet({super.key, required this.kind, required this.targetId, required this.label, required this.amount});
  final String kind;
  final String targetId;
  final String label;
  final double amount;

  @override
  State<PixSheet> createState() => _PixSheetState();
}

class _PixSheetState extends State<PixSheet> {
  PixCharge? _charge;
  bool _loading = true;
  bool _recording = false;
  bool _copied = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final charge = widget.kind == 'comanda'
          ? await app.session.generateComandaPix(widget.targetId, widget.amount)
          : await app.session.generateTablePix(widget.amount);
      if (!mounted) return;
      if (charge.qrCodeBase64.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível gerar o Pix.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _charge = charge;
      });
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.isValidation ? e.message : 'Não foi possível gerar o Pix.';
        });
      }
    }
  }

  Future<void> _check() async {
    final charge = _charge;
    if (charge == null || _recording) return;
    final paid = await app.session.pixPaid(charge.mpPaymentId);
    if (!mounted || !paid || _recording) return;
    _poll?.cancel();
    setState(() => _recording = true);
    final error = widget.kind == 'comanda'
        ? await app.session.payComanda(
            widget.targetId,
            method: charge.recordMethod,
            amount: charge.amount,
            pixChargeId: charge.mpPaymentId,
          )
        : await app.session.payTable(method: charge.recordMethod, amount: charge.amount, pixChargeId: charge.mpPaymentId);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _recording = false;
        _error = 'Pix confirmado, mas falhou ao registrar. Toque em "Já paguei".';
      });
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final charge = _charge;
    return SheetBody(
      title: 'Pix · ${widget.label}',
      children: [
        Text(brl(widget.amount), textAlign: TextAlign.center, style: T.num(24, c: C.navy)),
        const SizedBox(height: 12),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Text('Gerando QR Code Pix...', textAlign: TextAlign.center, style: T.body(c: C.sub)),
          )
        else if (charge == null) ...[
          Text(_error ?? 'Não foi possível gerar o Pix.', textAlign: TextAlign.center, style: T.body(c: C.cancel)),
          const SizedBox(height: 12),
          Center(child: SizedBox(width: 180, child: Btn('Tentar novamente', onTap: _start))),
        ] else ...[
          Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: C.line),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                base64Decode(charge.qrCodeBase64.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '')),
                width: 224,
                height: 224,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 224,
                  height: 224,
                  child: Center(child: Text('QR indisponível. Use o copia e cola.')),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Btn(
            _copied ? 'Código copiado!' : 'Copiar código Pix (copia e cola)',
            kind: BtnKind.secondary,
            dense: true,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: charge.qrCode));
              if (!mounted) return;
              setState(() => _copied = true);
              Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Text(_error!, textAlign: TextAlign.center, style: T.s(12, c: C.cancel, h: 1.35))
          else
            Text(
              _recording ? 'Pagamento confirmado! Registrando...' : 'Aguardando pagamento...',
              textAlign: TextAlign.center,
              style: T.s(12, w: T.semibold, c: C.orangeText, h: 1.35),
            ),
        ],
      ],
      footer: BtnRow(
        Btn('Fechar', kind: BtnKind.secondary, onTap: _recording ? null : () => Navigator.pop(context, false)),
        Btn(
          _recording ? 'Registrando...' : 'Já paguei',
          kind: BtnKind.magenta,
          loading: _recording,
          onTap: charge == null ? null : _check,
        ),
      ),
    );
  }
}
