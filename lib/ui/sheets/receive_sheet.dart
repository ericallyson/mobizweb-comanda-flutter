import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../stores/payments.dart';
import '../kit.dart';

/// Recebimento da conta da MESA (`kind: session`) ou de uma COMANDA
/// (`kind: comanda`). Espelha `TableReceiveModal.vue` e a visão "pay" do
/// `ComandasModal.vue`, com um passo a mais: cartão e Pix são cobrados na
/// própria maquininha (deeplink da Stone) antes de registrar.
///
/// Fecha com `true` quando algo foi recebido (a tela de trás recarrega).
class ReceiveSheet extends StatefulWidget {
  const ReceiveSheet({
    super.key,
    required this.kind,
    required this.targetId,
    required this.label,
    required this.remaining,
    this.detail,
  });

  final String kind;
  final String targetId;
  final String label;
  final double remaining;

  /// Linha extra (ex.: "Itens R$ 90,00 + Serviço (10%) R$ 9,00").
  final String? detail;

  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<ReceiveSheet> {
  late final _amount = TextEditingController(text: decimalInput(widget.remaining));
  late final _cash = TextEditingController(text: decimalInput(widget.remaining));
  String? _method;
  bool _busy = false;
  bool _onTerminal = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.methods.addListener(_changed);
    app.methods.load();
  }

  @override
  void dispose() {
    app.methods.removeListener(_changed);
    _amount.dispose();
    _cash.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<ReceiveOption> get _options => app.methods.receiveOptions;

  ReceiveOption get _selected {
    final options = _options;
    return options.where((o) => o.method == _method).firstOrNull ??
        // Padrão: a primeira forma cobrada na maquininha; senão a primeira.
        options.where((o) => _chargesOnTerminal(o)).firstOrNull ??
        options.first;
  }

  bool _chargesOnTerminal(ReceiveOption o) => terminalTypeFor(o.method) != null && app.terminal.canCharge;

  double get _value => round2(parseDecimal(_amount.text));
  double get _change {
    final c = parseDecimal(_cash.text) - _value;
    return c > 0 ? round2(c) : 0;
  }

  Future<void> _record(Future<String?> Function() send) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await send();
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<String?> _pay({required String method, required double amount, double? cashReceived, String? pixChargeId}) =>
      widget.kind == 'comanda'
      ? app.session.payComanda(
          widget.targetId,
          method: method,
          amount: amount,
          cashReceived: cashReceived,
          pixChargeId: pixChargeId,
        )
      : app.session.payTable(method: method, amount: amount, cashReceived: cashReceived, pixChargeId: pixChargeId);

  Future<void> _confirm() async {
    if (_busy) return;
    final option = _selected;
    final amount = option.isOnlinePix ? widget.remaining : _value;
    if (amount <= 0) {
      setState(() => _error = 'Informe o valor.');
      return;
    }
    if (!option.isCash && amount > widget.remaining + 0.01) {
      setState(() => _error = 'O valor não pode passar do restante (${brl(widget.remaining)}). Só dinheiro dá troco.');
      return;
    }

    // Pix online: QR gerado pelo servidor.
    if (option.isOnlinePix) {
      final paid = await showSheet<bool>(
        context,
        (_) => PixSheet(kind: widget.kind, targetId: widget.targetId, label: widget.label, amount: amount),
        dismissible: false,
      );
      if (paid == true && mounted) Navigator.pop(context, true);
      return;
    }

    // Dinheiro: o servidor exige o valor recebido (troco = diferença).
    if (option.isCash) {
      final received = parseDecimal(_cash.text);
      if (received + 0.005 < amount) {
        setState(() => _error = 'O valor recebido é menor que o valor a pagar.');
        return;
      }
      await _record(() => _pay(method: option.method, amount: amount, cashReceived: received));
      return;
    }

    // Cartão / Pix / voucher na maquininha.
    final type = terminalTypeFor(option.method);
    if (type != null && app.terminal.canCharge) {
      setState(() {
        _busy = true;
        _onTerminal = true;
        _error = null;
      });
      final outcome = await app.ledger.chargeAndRecord(
        kind: widget.kind,
        targetId: widget.targetId,
        label: widget.label,
        method: option.method,
        amount: amount,
        type: type,
      );
      if (!mounted) return;
      switch (outcome.status) {
        case ChargeStatus.recorded:
          await app.session.fetch(app.session.session?.id ?? widget.targetId, silent: true);
          if (widget.kind == 'comanda') await app.session.loadComandas();
          if (mounted) Navigator.pop(context, true);
        case ChargeStatus.declined:
          setState(() {
            _busy = false;
            _onTerminal = false;
            _error = outcome.message;
          });
        case ChargeStatus.approvedNotRecorded:
        case ChargeStatus.unknown:
          final approved = outcome.status == ChargeStatus.approvedNotRecorded;
          await confirm(
            context,
            title: approved ? 'Cobrado, mas não registrado' : 'Sem resposta da maquininha',
            message: approved
                ? 'O cartão foi cobrado, mas o Mobizweb não confirmou o registro (${outcome.message}). '
                      'O pagamento ficou guardado em Configurações › Pagamentos pendentes e será reenviado. '
                      'NÃO cobre de novo.'
                : 'Confira no app da Stone se a cobrança foi aprovada antes de cobrar de novo. '
                      'Ela ficou em Configurações › Pagamentos pendentes.',
            confirmLabel: 'Entendi',
            cancelLabel: 'Fechar',
          );
          if (mounted) Navigator.pop(context, true);
      }
      return;
    }

    // Demais formas (ou cobrança na maquininha desligada): só registra.
    await _record(() => _pay(method: option.method, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final selected = _selected;
    final onTerminal = _chargesOnTerminal(selected);
    final offline = !app.api.online.value;

    if (_onTerminal) {
      return SheetBody(
        title: 'Aguardando a maquininha…',
        children: [
          const SizedBox(height: 8),
          const Center(child: CircularProgressIndicator(color: C.primary600)),
          const SizedBox(height: 16),
          Text(
            'Conclua o pagamento de ${brl(_value)} no app da Stone. Esta tela volta sozinha.',
            textAlign: TextAlign.center,
            style: T.sm(c: C.zinc600),
          ),
          const SizedBox(height: 16),
          Btn(
            'Voltei e nada aconteceu',
            kind: BtnKind.outline,
            dense: true,
            onTap: () => app.terminal.abandon(),
          ),
        ],
      );
    }

    return SheetBody(
      title: 'Receber conta · ${widget.label}',
      children: [
        bigMoney(widget.remaining),
        if (widget.detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(widget.detail!, textAlign: TextAlign.center, style: T.s(11, c: C.zinc400)),
          ),
        const SizedBox(height: 12),
        if (offline) ...[const Note('Recebimento exige conexão.'), const SizedBox(height: 12)],
        ColGrid(
          cols: 3,
          children: [
            for (final o in options)
              Choice(o.label, selected: o.method == selected.method, onTap: _busy ? null : () => setState(() {
                _method = o.method;
                _error = null;
              })),
          ],
        ),
        const SizedBox(height: 12),
        if (!selected.isOnlinePix) ...[
          MoneyField(label: 'Valor', controller: _amount, onChanged: (_) => setState(() {})),
          if (selected.isCash) ...[
            const SizedBox(height: 10),
            MoneyField(label: 'Valor recebido', controller: _cash, onChanged: (_) => setState(() {})),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(text: 'Troco: ', children: [TextSpan(text: brl(_change), style: T.xs(w: T.bold, c: C.zinc700))]),
              style: T.xs(c: C.zinc500),
            ),
          ],
          const SizedBox(height: 8),
        ],
        if (onTerminal)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.contactless_outlined, size: 16, color: C.primary500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    app.terminal.isDemo
                        ? 'Modo demonstração: a cobrança é simulada.'
                        : 'A cobrança abre o app de pagamento da maquininha.',
                    style: T.xs(c: C.primary500),
                  ),
                ),
              ],
            ),
          ),
        ErrText(_error, center: true),
      ],
      footer: BtnRow(
        Btn('Voltar', kind: BtnKind.outline, onTap: _busy ? null : () => Navigator.pop(context)),
        Btn(
          selected.isOnlinePix
              ? 'Gerar Pix'
              : _busy
              ? 'Registrando...'
              : onTerminal
              ? 'Cobrar na maquininha'
              : 'Confirmar',
          loading: _busy,
          onTap: offline ? null : _confirm,
        ),
      ),
    );
  }
}

/// Pix online: gera o QR no servidor, mostra, consulta a cada 4 s e registra
/// o pagamento quando o provedor confirma. Espelha `PixReceiveModal.vue`.
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
        bigMoney(widget.amount),
        const SizedBox(height: 12),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Text('Gerando QR Code Pix...', textAlign: TextAlign.center, style: T.sm(c: C.zinc400)),
          )
        else if (charge == null) ...[
          Text(_error ?? 'Não foi possível gerar o Pix.', textAlign: TextAlign.center, style: T.sm(c: C.red500)),
          const SizedBox(height: 12),
          Center(child: SizedBox(width: 180, child: Btn('Tentar novamente', onTap: _start))),
        ] else ...[
          Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: C.zinc100),
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
                  child: Center(child: Text('QR indisponível — use o copia e cola.')),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Btn(
            _copied ? 'Código copiado!' : 'Copiar código Pix (copia e cola)',
            kind: BtnKind.outline,
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
            Text(_error!, textAlign: TextAlign.center, style: T.xs(c: C.red500))
          else
            Text(
              _recording ? 'Pagamento confirmado! Registrando...' : 'Aguardando pagamento...',
              textAlign: TextAlign.center,
              style: T.xs(w: T.medium, c: C.amber600),
            ),
        ],
      ],
      footer: BtnRow(
        Btn('Fechar', kind: BtnKind.outline, onTap: _recording ? null : () => Navigator.pop(context, false)),
        Btn(_recording ? 'Registrando...' : 'Já paguei', loading: _recording, onTap: charge == null ? null : _check),
      ),
    );
  }
}
