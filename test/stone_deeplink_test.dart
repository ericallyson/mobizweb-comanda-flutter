import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobizweb_pos/stone/stone_deeplink.dart';

void main() {
  group('pagamento', () {
    test('monta payment-app://pay com centavos e scheme de retorno', () {
      final uri = Uri.parse(
        buildPaymentUri(amountCents: 1999, returnScheme: 'mobizpos', type: StoneTransactionType.debit),
      );
      expect(uri.scheme, 'payment-app');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['amount'], '1999');
      expect(uri.queryParameters['return_scheme'], 'mobizpos');
      expect(uri.queryParameters['transaction_type'], 'DEBIT');
      expect(uri.queryParameters['editable_amount'], '0');
      // Débito nunca leva parcelamento; order_id fica de fora de propósito.
      expect(uri.queryParameters.containsKey('installment_type'), isFalse);
      expect(uri.queryParameters.containsKey('installment_count'), isFalse);
      expect(uri.queryParameters.containsKey('order_id'), isFalse);
    });

    test('crédito sem parcelamento informado deixa a Stone perguntar', () {
      final q = Uri.parse(
        buildPaymentUri(amountCents: 5000, returnScheme: 'mobizpos', type: StoneTransactionType.credit),
      ).queryParameters;
      expect(q['transaction_type'], 'CREDIT');
      expect(q.containsKey('installment_type'), isFalse);
    });

    test('crédito parcelado sem juros envia MERCHANT + contagem', () {
      final q = Uri.parse(
        buildPaymentUri(
          amountCents: 30000,
          returnScheme: 'mobizpos',
          type: StoneTransactionType.credit,
          installmentType: StoneInstallmentType.merchant,
          installmentCount: 3,
        ),
      ).queryParameters;
      expect(q['installment_type'], 'MERCHANT');
      expect(q['installment_count'], '3');
    });

    test('crédito à vista envia NONE sem contagem', () {
      final q = Uri.parse(
        buildPaymentUri(
          amountCents: 30000,
          returnScheme: 'mobizpos',
          type: StoneTransactionType.credit,
          installmentType: StoneInstallmentType.none,
          installmentCount: 3,
        ),
      ).queryParameters;
      expect(q['installment_type'], 'NONE');
      expect(q.containsKey('installment_count'), isFalse);
    });

    test('lê o retorno de sucesso da documentação', () {
      final r = parsePaymentReturn(
        'mobizpos://pay-response?code=0&amount=100&cardholder_name=JOAO%2FSILVA'
        '&itk=PB0419AL60480-1.17.7-2278-0003&atk=37820073187607'
        '&authorization_date_time=05%2F10%2F2022%2002%3A36%3A17&brand=MASTERCARD'
        '&authorization_code=187607&installment_count=0&pan=627303****2166&type=D%C3%A9bito&entry_mode=ICC',
      );
      expect(r.approved, isTrue);
      expect(r.code, '0');
      expect(r.atk, '37820073187607');
      expect(r.authorizationCode, '187607');
      expect(r.brand, 'MASTERCARD');
      expect(r.amountCents, 100);
      expect(r.type, 'Débito');
      expect(r.cardSummary, 'MASTERCARD ****2166');
    });

    test('usuário encerrou o app: não aprovado, com a mensagem da Stone', () {
      final r = parsePaymentReturn('mobizpos://pay-response?code=2&message=Usu%C3%A1rio%20encerrou%20o%20aplicativo');
      expect(r.approved, isFalse);
      expect(r.failureMessage, 'Usuário encerrou o aplicativo');
    });

    test('não autorizada', () {
      final r = parsePaymentReturn(
        'mobizpos://pay-response?success=false&reason=1016&response_code=-6&code=-6&message=N%C3%A3o%20autorizada',
      );
      expect(r.approved, isFalse);
      expect(r.code, '-6');
      expect(r.failureMessage, 'Não autorizada');
    });

    test('code=0 SEM atk não conta como aprovado (não há como conciliar)', () {
      expect(parsePaymentReturn('mobizpos://pay-response?code=0&amount=100').approved, isFalse);
    });

    test('retorno sem query não quebra', () {
      final r = parsePaymentReturn('mobizpos://pay-response');
      expect(r.approved, isFalse);
      expect(r.failureMessage, contains('não concluído'));
    });
  });

  group('cancelamento', () {
    test('monta cancel-app://cancel com as duas grafias do scheme de retorno', () {
      final q = Uri.parse(buildCancelUri(atk: '123', amountCents: 500, returnScheme: 'mobizpos')).queryParameters;
      expect(q['atk'], '123');
      expect(q['amount'], '500');
      expect(q['returnscheme'], 'mobizpos');
      expect(q['return_scheme'], 'mobizpos');
    });

    test('lê sucesso e falhas documentadas', () {
      expect(
        parseCancelReturn(
          'mobizpos://cancel?success=true&atk=39031080354321&canceledamount=0&paymenttype=2'
          '&transactionamount=100&orderid=&authorizationcode=395178&reason=APPROVED&responsecode=0000',
        ).success,
        isTrue,
      );
      final aborted = parseCancelReturn('mobizpos://cancel?success=false&reason=7011&responsecode=-2');
      expect(aborted.success, isFalse);
      expect(aborted.failureMessage, contains('cancelado'));
      expect(
        parseCancelReturn('mobizpos://cancel?success=false&reason=7202&responsecode=-2').failureMessage,
        contains('não encontrada'),
      );
    });
  });

  group('impressão', () {
    test('monta printer-app://print com os três parâmetros obrigatórios', () {
      final uri = Uri.parse(
        buildPrintUri(
          content: const [
            StonePrintable.text('Mesa 12 — R\$ 10,00', align: 'center', size: 'big'),
            StonePrintable.line('linha & simples'),
            StonePrintable.image('QUJD'),
          ],
          returnScheme: 'mobizpos',
        ),
      );
      expect(uri.scheme, 'printer-app');
      expect(uri.host, 'print');
      expect(uri.queryParameters['SHOW_FEEDBACK_SCREEN'], 'false');
      expect(uri.queryParameters['SCHEME_RETURN'], 'mobizpos');
      final content = jsonDecode(uri.queryParameters['PRINTABLE_CONTENT']!) as List;
      expect(content[0], {'type': 'text', 'content': 'Mesa 12 — R\$ 10,00', 'align': 'center', 'size': 'big'});
      expect(content[1], {'type': 'line', 'content': 'linha & simples'});
      expect(content[2], {'type': 'image', 'imagePath': 'QUJD'});
    });

    test('espaços viram %20 (não "+") para o Android decodificar igual', () {
      final raw = buildPrintUri(content: const [StonePrintable.line('a b')], returnScheme: 'mobizpos');
      expect(raw.contains('+'), isFalse);
      expect(raw.contains('a%20b'), isTrue);
    });

    test('lê o retorno independente do nome do parâmetro', () {
      expect(parsePrintReturn('mobizpos://print?DEEPLINK_RETURN=SUCCESS'), isNull);
      expect(parsePrintReturn('mobizpos://print?result=success'), isNull);
      expect(parsePrintReturn('mobizpos://print?DEEPLINK_RETURN=PRINTER_OUT_OF_PAPER'), 'Impressora sem papel.');
      expect(parsePrintReturn('mobizpos://print?code=PRINTER_INVALID_DATA'), contains('grande demais'));
      expect(parsePrintReturn('mobizpos://print'), isNotNull);
    });

    test('reimpressão', () {
      final q = Uri.parse(buildReprintUri(atk: '99', returnScheme: 'mobizpos')).queryParameters;
      expect(q['ATK'], '99');
      expect(q['TYPE_CUSTOMER'], 'CLIENT');
    });
  });

  test('returnHost identifica a operação', () {
    expect(returnHost('mobizpos://pay-response?code=0'), 'pay-response');
    expect(returnHost('mobizpos://print?x=SUCCESS'), 'print');
  });
}
