import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/native.dart';
import '../print/receipt.dart';
import '../print/render.dart';
import '../stores/settings.dart';
import 'stone_deeplink.dart';

/// A maquininha: cobrança, estorno e impressora — tudo pelos apps da Stone
/// (deeplink). Em aparelho sem Stone, o "modo demonstração" simula os dois
/// para o fluxo poder ser exercitado.
class Terminal {
  Terminal(this._native, this._settings);

  final Native _native;
  final Settings _settings;

  /// O que a detecção automática achou neste aparelho. Pode dar falso
  /// negativo (o Android 11+ esconde de um app a existência de outros), por
  /// isso o que vale para o resto do app são [hasStone] e [hasPrinter].
  bool stoneAvailable = false;
  bool printerAvailable = false;
  String deviceLabel = '';

  /// Há app de pagamento da Stone (detectado, ou o operador mandou usar)?
  bool get hasStone => stoneAvailable || _settings.forceStone;

  /// Há app de impressão da Stone (detectado, ou o operador mandou usar)?
  bool get hasPrinter => printerAvailable || _settings.forceStone;

  /// Modo demonstração: mostra o que iria para o papel.
  Future<void> Function(List<Uint8List> pngs)? onPreview;

  Future<void> init() async {
    stoneAvailable = await _native.canHandle('payment-app://pay');
    printerAvailable = await _native.canHandle('printer-app://print');
    final info = await _native.deviceInfo();
    deviceLabel = [info['manufacturer'], info['model']].where((e) => e != null && '$e'.isNotEmpty).join(' ');
  }

  bool get _demo => !hasStone && _settings.demoMode;

  /// Simulando a maquininha (aparelho sem Stone + modo demonstração)?
  bool get isDemo => _demo;

  /// Cartão/Pix devem ser cobrados aqui antes de registrar o pagamento?
  bool get canCharge => _settings.chargeOnTerminal && (hasStone || _demo);

  bool get canPrint => hasPrinter || _demo;

  /// Abre o app de pagamento da Stone e devolve o resultado da transação.
  /// `code == 'abandoned'`: o operador cancelou a espera sem resposta — o
  /// desfecho é DESCONHECIDO (a cobrança pode ter sido aprovada).
  Future<StonePaymentResult> charge({required int amountCents, StoneTransactionType? type}) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return StonePaymentResult(approved: true, code: '0', atk: null, amountCents: amountCents, brand: 'DEMO');
    }
    final uri = buildPaymentUri(amountCents: amountCents, returnScheme: Config.returnScheme, type: type);
    try {
      final raw = await _launch(uri);
      if (raw == null) {
        return const StonePaymentResult(approved: false, code: '?', message: 'App de pagamento da Stone não encontrado neste aparelho.');
      }
      return parsePaymentReturn(raw);
    } on _Abandoned {
      return const StonePaymentResult(
        approved: false,
        code: 'abandoned',
        message: 'Não recebemos a resposta da maquininha.',
      );
    }
  }

  /// Estorna uma transação aprovada (app de cancelamento da Stone).
  Future<StoneCancelResult> refund({required String atk, required int amountCents}) async {
    if (_demo) return const StoneCancelResult(success: true);
    try {
      final raw = await _launch(buildCancelUri(atk: atk, amountCents: amountCents, returnScheme: Config.returnScheme));
      if (raw == null) return const StoneCancelResult(success: false, reason: 'indisponível');
      return parseCancelReturn(raw);
    } on _Abandoned {
      return const StoneCancelResult(success: false, reason: 'sem resposta');
    }
  }

  /// Segunda via do comprovante do cartão.
  Future<String?> reprint(String atk, {bool customerCopy = true}) async {
    if (_demo) return null;
    try {
      final raw = await _launch(
        buildReprintUri(atk: atk, returnScheme: Config.returnScheme, customerCopy: customerCopy),
      );
      return raw == null ? 'App de impressão da Stone não encontrado neste aparelho.' : parsePrintReturn(raw);
    } on _Abandoned {
      return 'Sem resposta da impressora.';
    }
  }

  /// Imprime o documento. Devolve `null` se imprimiu ou a mensagem do erro.
  Future<String?> printLines(List<PLine> lines) async {
    if (!canPrint) return 'Impressora indisponível neste aparelho.';
    if (_demo) {
      final preview = onPreview;
      if (preview != null) await preview(await renderReceiptPng(lines, maxHeight: 4000));
      return null;
    }

    final calls = _settings.printAsText
        ? [toStoneText(lines, barcodes: await renderBarcodesBase64(lines))]
        : toStoneImageCalls(await renderReceiptPng(lines));
    // Sequencial e síncrono, como a Stone orienta: cada chamada espera a
    // resposta da anterior.
    try {
      for (final content in calls) {
        final raw = await _launch(buildPrintUri(content: content, returnScheme: Config.returnScheme));
        if (raw == null) return 'App de impressão da Stone não encontrado neste aparelho.';
        final error = parsePrintReturn(raw);
        if (error != null) return error;
      }
      return null;
    } on _Abandoned {
      return 'Sem resposta da impressora.';
    }
  }

  /// O operador saiu do app da Stone sem resposta: libera o canal.
  Future<void> abandon() => _native.abandon();

  Future<String?> _launch(String uri) async {
    try {
      return await _native.launch(uri);
    } on PlatformException catch (e) {
      if (e.code == 'abandoned') throw const _Abandoned();
      if (e.code == 'busy') {
        // Uma espera antiga ficou presa: solta e tenta uma vez.
        await _native.abandon();
        try {
          return await _native.launch(uri);
        } on PlatformException {
          return null;
        }
      }
      return null;
    }
  }
}

class _Abandoned implements Exception {
  const _Abandoned();
}
