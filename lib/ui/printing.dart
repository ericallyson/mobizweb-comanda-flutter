import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/api.dart';
import '../models/models.dart';
import '../print/receipt.dart';
import 'kit.dart';

/// Imprime e avisa na tela se a impressora recusou.
Future<bool> _print(BuildContext context, List<PLine> lines) async {
  final error = await app.terminal.printLines(lines);
  if (error != null && context.mounted) toast(context, 'Impressão: $error', error: true);
  return error == null;
}

String? get _operator => app.auth.user?.name;
String get _storeName => app.auth.store?.name ?? '';

/// Conta/conferência da mesa aberta (payload do servidor).
Future<bool> printSessionBill(BuildContext context) async {
  final session = app.session.session;
  if (session == null) return false;
  try {
    final receipt = await app.session.fetchReceipt();
    if (!context.mounted) return false;
    return await _print(context, billReceipt(receipt, guestCount: session.guestCount));
  } on ApiException catch (e) {
    if (context.mounted) toast(context, 'Não foi possível montar a conta: ${e.message}', error: true);
    return false;
  }
}

/// Conta de uma comanda da mesa.
Future<bool> printComandaBill(BuildContext context, Comanda comanda) async {
  final session = app.session.session;
  if (session == null) return false;
  return _print(
    context,
    comandaReceipt(
      storeName: _storeName,
      tableLabel: session.title.toUpperCase(),
      comanda: comanda,
      items: session.items,
      operator: _operator,
    ),
  );
}

/// Via do pedido recém-enviado. Devolve a mensagem de erro da impressora, ou
/// `null` se imprimiu: quem chama mostra o erro na janela "Pedido na cozinha".
Future<String?> printOrderTicket({
  required String tableLabel,
  String? comandaLabel,
  String? customerName,
  required List<CartItem> items,
}) => app.terminal.printLines(
  orderTicket(
    tableLabel: tableLabel.toUpperCase(),
    comandaLabel: comandaLabel,
    customerName: customerName,
    operator: _operator,
    items: items,
  ),
);

Future<bool> printCounterSale(
  BuildContext context, {
  required CounterSaleResult sale,
  required List<CartItem> items,
  required List<({String label, double amount})> payments,
  String? customerName,
}) => _print(
  context,
  counterReceipt(
    storeName: _storeName,
    number: sale.number,
    customerName: customerName,
    operator: _operator,
    items: items,
    payments: payments,
    total: sale.total,
    change: sale.changeAmount,
    itemsTotal: items.fold<double>(0, (a, i) => a + i.total),
  ),
);

/// Fichas da venda de balcão: uma por produto pago.
Future<bool> printCounterTickets(
  BuildContext context, {
  required CounterSaleResult sale,
  required List<CartItem> items,
}) => _print(context, counterTickets(number: sale.number, items: items));

/// O que sai sozinho no papel depois de uma venda de balcão, UM de cada vez:
/// o comprovante e depois as fichas, conforme as opções de Configurações.
///
/// Em loja com emissão fiscal o comprovante NÃO sai sozinho: "Venda recebida"
/// tem "Imprimir venda" e "Imprimir nota" e o operador escolhe um dos dois,
/// para não sair cupom comum e nota fiscal da mesma venda.
Future<void> printAfterCounterSale(
  BuildContext context, {
  required CounterSaleResult sale,
  required List<CartItem> items,
  required List<({String label, double amount})> payments,
  String? customerName,
}) async {
  if (!app.terminal.canPrint) return;
  final fiscal = app.counter.context?.fiscalActive ?? false;
  if (app.settings.printCounter && !fiscal) {
    await printCounterSale(context, sale: sale, items: items, payments: payments, customerName: customerName);
  }
  if (app.settings.printTickets && context.mounted) {
    await printCounterTickets(context, sale: sale, items: items);
  }
}

Future<bool> printCashClose(
  BuildContext context, {
  required CashDetail detail,
  required Map<String, double> counted,
  required bool showExpected,
}) => _print(
  context,
  cashCloseSlip(
    storeName: _storeName,
    operator: _operator,
    detail: detail,
    counted: counted,
    showExpected: showExpected,
  ),
);
