/// Deeplinks da Stone para POS Android — montagem das URIs e leitura das
/// respostas. Código puro (sem Flutter) para ser testado em `test/`.
///
/// Referência: https://sdkandroid.stone.com.br (Pagamento, Cancelamento,
/// Impressão e Reimpressão por Deeplink). Os nomes de parâmetro abaixo são os
/// da documentação — inclusive as inconsistências dela, anotadas caso a caso.
library;

import 'dart:convert';

/// Monta `scheme://host?k=v&…` com `%20` (não `+`) nos espaços.
String _uri(String scheme, String host, Map<String, String> params) {
  final q = params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
  return '$scheme://$host?$q';
}

// ── Pagamento ────────────────────────────────────────────────────────────────

enum StoneTransactionType {
  debit('DEBIT'),
  credit('CREDIT'),
  voucher('VOUCHER'),
  pix('PIX');

  const StoneTransactionType(this.wire);
  final String wire;
}

enum StoneInstallmentType {
  /// À vista.
  none('NONE'),

  /// Parcelado sem juros (lojista).
  merchant('MERCHANT'),

  /// Parcelado com juros (emissor).
  issuer('ISSUER');

  const StoneInstallmentType(this.wire);
  final String wire;
}

/// `payment-app://pay?…`. Campos opcionais não enviados são perguntados na
/// tela do app de pagamento da Stone (ex.: à vista × parcelado no crédito).
///
/// `order_id` fica de fora de propósito: é numérico, precisa ser habilitado
/// em Ajustes do POS e, ligado sem a função, devolve o erro "ID DE PEDIDO
/// DEFINIDO PORÉM DESABILITADO". A conciliação é feita pelo ATK.
String buildPaymentUri({
  required int amountCents,
  required String returnScheme,
  StoneTransactionType? type,
  StoneInstallmentType? installmentType,
  int? installmentCount,
  bool editableAmount = false,
}) {
  assert(amountCents > 0 && amountCents <= 999999999);
  return _uri('payment-app', 'pay', {
    'return_scheme': returnScheme,
    'amount': '$amountCents',
    'editable_amount': editableAmount ? '1' : '0',
    'transaction_type': ?type?.wire,
    // Débito não leva parcelamento; crédito à vista = NONE sem contagem.
    if (type == StoneTransactionType.credit && installmentType != null) 'installment_type': installmentType.wire,
    if (type == StoneTransactionType.credit &&
        installmentType != null &&
        installmentType != StoneInstallmentType.none &&
        installmentCount != null &&
        installmentCount >= 2)
      'installment_count': '$installmentCount',
  });
}

class StonePaymentResult {
  const StonePaymentResult({
    required this.approved,
    required this.code,
    this.message,
    this.atk,
    this.itk,
    this.authorizationCode,
    this.brand,
    this.pan,
    this.type,
    this.installmentCount,
    this.amountCents,
    this.raw = '',
  });

  final bool approved;
  final String code;
  final String? message;

  /// Identificador da transação na adquirente — vai em `tef_transaction_id`.
  final String? atk;
  final String? itk;

  /// Código de autorização — vai em `tef_nsu`.
  final String? authorizationCode;
  final String? brand;
  final String? pan;

  /// Vem localizado ("Débito", "Crédito") — só para exibir, nunca comparar.
  final String? type;
  final int? installmentCount;

  /// Valor efetivamente cobrado, quando a Stone devolve.
  final int? amountCents;
  final String raw;

  /// Texto para a tela quando a cobrança não foi aprovada.
  String get failureMessage {
    final m = message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return 'Pagamento não concluído na maquininha (código $code).';
  }

  /// Resumo curto para `reference` do pagamento: "MASTERCARD ****2166".
  String? get cardSummary {
    final parts = [
      if (brand != null && brand!.isNotEmpty) brand!,
      if (pan != null && pan!.length >= 4) '****${pan!.substring(pan!.length - 4)}',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// Lê `mobizpos://pay-response?…`. "Transação de sucesso o retorno é 0,
/// diferente disso é considerado como erro." Exige também o ATK: sem ele não
/// há como conciliar com a adquirente, então não se registra recebimento.
StonePaymentResult parsePaymentReturn(String raw) {
  final q = _query(raw);
  final code = q['code'] ?? q['response_code'] ?? '';
  final atk = _nonEmpty(q['atk']);
  final approved = code == '0' && q['success'] != 'false' && atk != null;
  return StonePaymentResult(
    approved: approved,
    code: code.isEmpty ? '?' : code,
    message: _nonEmpty(q['message']) ?? _nonEmpty(q['reason']),
    atk: atk,
    itk: _nonEmpty(q['itk']),
    authorizationCode: _nonEmpty(q['authorization_code']),
    brand: _nonEmpty(q['brand']),
    pan: _nonEmpty(q['pan']),
    type: _nonEmpty(q['type']),
    installmentCount: int.tryParse(q['installment_count'] ?? ''),
    amountCents: int.tryParse(q['amount'] ?? ''),
    raw: raw,
  );
}

// ── Cancelamento (estorno) ───────────────────────────────────────────────────

/// `cancel-app://cancel?…`. A documentação diverge sobre o nome do scheme de
/// retorno (`returnscheme` no exemplo, `return_scheme` na tabela) — vão os
/// dois, o app da Stone ignora o que não conhece.
String buildCancelUri({required String atk, required int amountCents, required String returnScheme}) =>
    _uri('cancel-app', 'cancel', {
      'returnscheme': returnScheme,
      'return_scheme': returnScheme,
      'atk': atk,
      'amount': '$amountCents',
      'editable_amount': 'false',
    });

class StoneCancelResult {
  const StoneCancelResult({required this.success, this.reason, this.responseCode, this.raw = ''});
  final bool success;
  final String? reason;
  final String? responseCode;
  final String raw;

  String get failureMessage => switch (reason) {
    '7011' => 'Estorno cancelado na maquininha.',
    '7202' => 'Transação não encontrada na maquininha para estornar.',
    _ => 'Estorno não concluído${reason != null ? ' ($reason)' : ''}.',
  };
}

StoneCancelResult parseCancelReturn(String raw) {
  final q = _query(raw);
  return StoneCancelResult(
    success: q['success'] == 'true',
    reason: _nonEmpty(q['reason']),
    responseCode: _nonEmpty(q['responsecode']) ?? _nonEmpty(q['response_code']),
    raw: raw,
  );
}

// ── Impressão ────────────────────────────────────────────────────────────────

/// Um item de `PRINTABLE_CONTENT`. Todos os campos são String, como na doc.
class StonePrintable {
  const StonePrintable.text(String this.content, {this.align = 'left', this.size = 'medium'})
    : type = 'text',
      imageBase64 = null;
  const StonePrintable.line(String this.content) : type = 'line', align = null, size = null, imageBase64 = null;
  const StonePrintable.image(String this.imageBase64) : type = 'image', content = null, align = null, size = null;

  final String type;
  final String? content;

  /// `center` | `right` | `left`.
  final String? align;

  /// `big` | `medium` | `small`.
  final String? size;
  final String? imageBase64;

  Map<String, String> toJson() => {
    'type': type,
    'content': ?content,
    'align': ?align,
    'size': ?size,
    'imagePath': ?imageBase64,
  };
}

/// `printer-app://print?…` — os três parâmetros são obrigatórios.
String buildPrintUri({
  required List<StonePrintable> content,
  required String returnScheme,
  bool showFeedbackScreen = false,
}) => _uri('printer-app', 'print', {
  'SHOW_FEEDBACK_SCREEN': showFeedbackScreen ? 'true' : 'false',
  'SCHEME_RETURN': returnScheme,
  'PRINTABLE_CONTENT': jsonEncode([for (final c in content) c.toJson()]),
});

/// `reprinter-app://reprint?…` — segunda via do comprovante da transação.
String buildReprintUri({
  required String atk,
  required String returnScheme,
  bool customerCopy = true,
  bool showFeedbackScreen = true,
}) => _uri('reprinter-app', 'reprint', {
  'SHOW_FEEDBACK_SCREEN': showFeedbackScreen ? 'true' : 'false',
  'SCHEME_RETURN': returnScheme,
  'ATK': atk,
  'TYPE_CUSTOMER': customerCopy ? 'CLIENT' : 'MERCHANT',
});

/// Códigos de retorno documentados da impressão, com a mensagem ao operador.
const stonePrintErrors = <String, String>{
  'PRINTER_OUT_OF_PAPER': 'Impressora sem papel.',
  'PRINTER_INIT_ERROR': 'Falha ao iniciar a impressora.',
  'PRINTER_LOW_ENERGY': 'Bateria baixa para imprimir.',
  'PRINTER_BUSY': 'Impressora ocupada. Tente de novo.',
  'PRINTER_UNSUPPORTED_FORMAT': 'Formato de impressão não suportado.',
  'PRINTER_INVALID_DATA': 'Conteúdo grande demais para a impressora.',
  'PRINTER_OVERHEATING': 'Impressora superaquecida. Aguarde alguns instantes.',
  'PRINTER_PAPER_JAM': 'Papel preso na impressora.',
  'PRINTER_PRINT_ERROR': 'Erro ao imprimir.',
};

/// `null` = impresso; senão, a mensagem do erro. A doc lista os valores mas
/// não o nome do parâmetro de retorno, então a leitura procura o código na
/// URI inteira.
String? parsePrintReturn(String raw) {
  final upper = Uri.decodeFull(raw).toUpperCase();
  for (final e in stonePrintErrors.entries) {
    if (upper.contains(e.key)) return e.value;
  }
  if (upper.contains('SUCCESS')) return null;
  return 'A impressora não confirmou a impressão.';
}

// ── util ─────────────────────────────────────────────────────────────────────

/// Host do deeplink de retorno (`pay-response`, `cancel`, `print`, `reprint`).
String returnHost(String raw) => Uri.tryParse(raw)?.host ?? '';

Map<String, String> _query(String raw) {
  final i = raw.indexOf('?');
  if (i < 0) return const {};
  final out = <String, String>{};
  for (final pair in raw.substring(i + 1).split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final k = eq < 0 ? pair : pair.substring(0, eq);
    final v = eq < 0 ? '' : pair.substring(eq + 1);
    out[_decode(k)] = _decode(v);
  }
  return out;
}

String _decode(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } catch (_) {
    return s;
  }
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
