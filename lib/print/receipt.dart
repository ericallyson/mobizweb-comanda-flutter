/// Documentos impressos na térmica da maquininha, descritos como uma lista de
/// linhas ([PLine]) independente de como saem no papel (imagem ou texto).
/// Código puro — os layouts têm teste em `test/receipt_test.dart`.
library;

import '../core/format.dart';
import '../models/models.dart';

enum PSize { small, medium, big }

enum PAlign { left, center, right }

sealed class PLine {
  const PLine();
}

class PText extends PLine {
  const PText(this.text, {this.align = PAlign.left, this.size = PSize.medium, this.bold = false});
  final String text;
  final PAlign align;
  final PSize size;
  final bool bold;
}

/// Duas colunas: descrição à esquerda (quebra linha), valor à direita.
class PRow extends PLine {
  const PRow(this.left, this.right, {this.size = PSize.medium, this.bold = false});
  final String left;
  final String right;
  final PSize size;
  final bool bold;
}

class PDivider extends PLine {
  const PDivider();
}

class PGap extends PLine {
  const PGap([this.px = 12]);
  final double px;
}

/// Texto em destaque que SEMPRE ocupa uma linha só (nome do produto na
/// ficha): sai no maior tamanho que couber na largura do papel, entre
/// [maxSize] e [minSize] pontos; se nem no menor couber, é cortado com
/// reticências. No modo texto escolhe o tamanho da Stone pelo comprimento.
class PFit extends PLine {
  const PFit(this.text, {this.maxSize = 40, this.minSize = 22, this.bold = true});
  final String text;
  final double maxSize;
  final double minSize;
  final bool bold;
}

/// Linha em letra de largura fixa, já composta em [columns] colunas pelo
/// servidor (o DANFE). `center` centraliza o texto curto; `big` sai maior
/// quando cabe. Nunca quebra: linha mais larga que o papel é encolhida.
class PMono extends PLine {
  const PMono(this.text, {this.columns = 32, this.center = false, this.bold = false, this.big = false});
  final String text;
  final int columns;
  final bool center;
  final bool bold;
  final bool big;
}

/// QR-Code centralizado (consulta da NFC-e). A imagem é gerada no lado
/// nativo; onde não há como gerar (prévia, testes) a linha não sai, e o
/// DANFE já traz a chave e o endereço de consulta escritos.
class PQr extends PLine {
  const PQr(this.data, {this.size = 240});
  final String data;
  final double size;
}

/// Código de barras Code 128 centralizado. No modo imagem é desenhado; no
/// modo texto vai como uma imagem pequena no meio das linhas.
class PBarcode extends PLine {
  const PBarcode(this.data, {this.height = 64});
  final String data;
  final double height;
}

/// Fim de uma via destacável (uma ficha). A impressora da Stone não tem
/// guilhotina nem comando de corte no deeplink, então hoje vira uma linha de
/// picote com folga para rasgar. O renderizador nunca parte uma via no meio e
/// é neste ponto que entra o comando de corte parcial quando existir.
class PCut extends PLine {
  const PCut();
}

List<PLine> _header(Json store) {
  final name = asString(store['name']);
  final doc = asStringOrNull(store['document']);
  final address = asStringOrNull(store['address_line']);
  final phone = asStringOrNull(store['phone']);
  return [
    if (name.isNotEmpty) PText(name, align: PAlign.center, size: PSize.big, bold: true),
    if (doc != null) PText('CNPJ/CPF: $doc', align: PAlign.center, size: PSize.small),
    if (address != null) PText(address, align: PAlign.center, size: PSize.small),
    if (phone != null) PText(phone, align: PAlign.center, size: PSize.small),
  ];
}

const _footer = [
  PGap(8),
  PText('NÃO É DOCUMENTO FISCAL', align: PAlign.center, size: PSize.small),
  PGap(36),
];

/// Conta/conferência da mesa a partir do payload de
/// `GET /sessions/{id}/receipt` (o mesmo builder do cupom da Bridge).
List<PLine> billReceipt(Json receipt, {int? guestCount, String title = 'CONFERÊNCIA DE CONTA'}) {
  final lines = <PLine>[..._header(asMap(receipt['store'])), const PDivider()];
  lines.add(PText(title, align: PAlign.center, bold: true));

  final table = asStringOrNull(receipt['table_label']);
  if (table != null) lines.add(PText(table, align: PAlign.center, size: PSize.big, bold: true));
  final comandas = (receipt['comanda_labels'] is List)
      ? (receipt['comanda_labels'] as List).map((e) => '$e').join(', ')
      : '';
  if (comandas.isNotEmpty) lines.add(PText('Comandas: $comandas', align: PAlign.center, size: PSize.small));

  final customer = asStringOrNull(receipt['customer_name']);
  if (customer != null) lines.add(PText('Cliente: $customer', size: PSize.small));
  final waiter = asStringOrNull(receipt['waiter']) ?? asStringOrNull(receipt['operator']);
  if (waiter != null) lines.add(PText('Atendente: $waiter', size: PSize.small));
  final opened = dateTimeIso(asStringOrNull(receipt['opened_at']));
  if (opened.isNotEmpty) lines.add(PText('Abertura: $opened', size: PSize.small));
  lines.add(PText('Emissão: ${dateTime(DateTime.now())}', size: PSize.small));
  lines.add(const PDivider());

  for (final item in asList(receipt['items'])) {
    final rows = asList(item['rows']);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final qtyLabel = asStringOrNull(r['qty_label']) ?? qty(asDouble(r['qty'], 1));
      final name = asString(r['name']);
      final total = asDouble(r['total']);
      // A primeira linha é o item; as demais, adicionais/sabores (recuadas).
      lines.add(
        i == 0
            ? PRow('${qtyLabel}x $name', brl(total))
            : PRow('  + $name', total > 0.005 ? brl(total) : '', size: PSize.small),
      );
    }
    final flag = asStringOrNull(item['paid_label']) ?? asStringOrNull(item['pending_label']);
    if (flag != null) lines.add(PText('  [$flag]', size: PSize.small));
  }
  lines.add(const PDivider());

  final subtotal = asDouble(receipt['subtotal']);
  final couvert = asDouble(receipt['couvert']);
  final discount = asDouble(receipt['discount']);
  final addition = asDouble(receipt['addition']);
  final fee = asDouble(receipt['service_fee']);
  final total = asDouble(receipt['total']);
  final paid = asDouble(receipt['paid']);
  final remaining = asDouble(receipt['remaining']);

  lines.add(PRow('Subtotal', brl(subtotal)));
  if (couvert > 0.005) lines.add(PRow('Couvert', brl(couvert)));
  if (addition > 0.005) lines.add(PRow('Acréscimo', brl(addition)));
  if (discount > 0.005) lines.add(PRow('Desconto', '- ${brl(discount)}'));
  if (fee > 0.005) {
    lines.add(PRow('Taxa de serviço (${percent(asDouble(receipt['service_fee_percentage']))}%)', brl(fee)));
  }
  lines.add(PRow('TOTAL', brl(total), size: PSize.big, bold: true));

  final payments = asList(receipt['payments']);
  if (payments.isNotEmpty) {
    lines.add(const PDivider());
    for (final p in payments) {
      lines.add(PRow(asString(p['label'], 'Pagamento'), brl(asDouble(p['amount'])), size: PSize.small));
      final change = asDouble(p['change']);
      if (change > 0.005) lines.add(PRow('  Troco', brl(change), size: PSize.small));
    }
  }
  if (paid > 0.005) {
    lines.add(PRow('Pago', brl(paid)));
    lines.add(PRow('RESTANTE', brl(remaining), bold: true));
  }
  if (guestCount != null && guestCount > 1) {
    lines.add(PRow('Por pessoa ($guestCount)', brl(total / guestCount), size: PSize.small));
  }
  return lines..addAll(_footer);
}

/// Conta de UMA comanda. A API do garçom não expõe o recibo por comanda,
/// então sai dos itens da sessão + totais da comanda (calculados no servidor).
List<PLine> comandaReceipt({
  required String storeName,
  required String tableLabel,
  required Comanda comanda,
  required List<SessionItem> items,
  String? operator,
}) {
  final mine = items.where((i) => !i.isCanceled && i.comandaId == comanda.id).toList().reversed;
  return [
    if (storeName.isNotEmpty) PText(storeName, align: PAlign.center, size: PSize.big, bold: true),
    const PDivider(),
    const PText('CONFERÊNCIA DE CONTA', align: PAlign.center, bold: true),
    PText('$tableLabel / COMANDA ${comanda.label}', align: PAlign.center, size: PSize.big, bold: true),
    if (operator != null) PText('Atendente: $operator', size: PSize.small),
    PText('Emissão: ${dateTime(DateTime.now())}', size: PSize.small),
    const PDivider(),
    for (final i in mine) ...[
      PRow('${qty(i.quantity)}x ${i.productName}', brl(i.total)),
      if (i.flavorsLabel.isNotEmpty) PText('  ${i.flavorsLabel}', size: PSize.small),
      if (i.addonsLabel.isNotEmpty) PText('  + ${i.addonsLabel}', size: PSize.small),
    ],
    const PDivider(),
    PRow('Subtotal', brl(comanda.itemsSubtotal)),
    if (comanda.couvert != null && comanda.couvert!.total > 0.005) PRow('Couvert', brl(comanda.couvert!.total)),
    if (comanda.serviceFee > 0.005)
      PRow('Taxa de serviço (${percent(comanda.serviceFeePercentage)}%)', brl(comanda.serviceFee)),
    PRow('TOTAL', brl(comanda.total), size: PSize.big, bold: true),
    if (comanda.paid > 0.005) ...[
      PRow('Pago', brl(comanda.paid)),
      PRow('RESTANTE', brl(comanda.remaining), bold: true),
    ],
    ..._footer,
  ];
}

/// Descrição das escolhas de um item do carrinho (sabores, combo, adicionais).
List<String> cartItemDetails(CartItem item) {
  final out = <String>[];
  if (item.selectedFlavorIds.isNotEmpty && item.product.pizza != null) {
    final names = item.selectedFlavorIds
        .map((id) => item.product.pizza!.flavors.where((f) => f.id == id).map((f) => f.name).firstOrNull)
        .whereType<String>()
        .toList();
    if (names.isNotEmpty) out.add(names.join(' / '));
  }
  for (final sel in item.comboSelections) {
    out.add(sel.items.map((i) => i.name).join(', '));
  }
  if (item.addons.isNotEmpty) {
    final names = <String>[];
    for (final a in item.addons) {
      for (final g in item.product.addonGroups) {
        final found = g.items.where((i) => i.id == a.addonGroupItemId).firstOrNull;
        if (found != null) {
          names.add(a.quantity > 1 ? '${a.quantity}× ${found.name}' : found.name);
          break;
        }
      }
    }
    out.add('+ ${names.isEmpty ? '${item.addons.length} adicional(is)' : names.join(', ')}');
  }
  return out;
}

/// Via do pedido (produção/conferência) impressa ao enviar o carrinho.
List<PLine> orderTicket({
  required String tableLabel,
  String? comandaLabel,
  String? customerName,
  String? operator,
  required List<CartItem> items,
  DateTime? when,
}) => [
  const PText('PEDIDO', align: PAlign.center, bold: true),
  PText(tableLabel, align: PAlign.center, size: PSize.big, bold: true),
  if (comandaLabel != null) PText('COMANDA $comandaLabel', align: PAlign.center, bold: true),
  if (customerName != null && customerName.isNotEmpty) PText('Cliente: $customerName', size: PSize.small),
  PText(
    '${dateTime(when ?? DateTime.now())}${operator != null ? ' · $operator' : ''}',
    align: PAlign.center,
    size: PSize.small,
  ),
  const PDivider(),
  for (final i in items) ...[
    PText(
      '${qty(i.quantity)}${i.product.allowFractionalQty ? ' ${i.product.unitOfMeasure ?? 'kg'}' : 'x'} ${i.product.name}',
      bold: true,
    ),
    for (final d in cartItemDetails(i)) PText('   $d', size: PSize.small),
    if (i.notes.isNotEmpty) PText('   OBS: ${i.notes}', size: PSize.small, bold: true),
    const PGap(6),
  ],
  const PDivider(),
  const PGap(36),
];

/// Comprovante (não fiscal) da venda de balcão.
List<PLine> counterReceipt({
  required String storeName,
  int? number,
  String? customerName,
  String? operator,
  required List<CartItem> items,
  required List<({String label, double amount})> payments,
  required double total,
  double change = 0,

  /// Soma dos itens pelo preço do cardápio. Quando o servidor grava a venda
  /// por outro valor (promoção ou tabela de preço), a diferença sai no papel.
  double? itemsTotal,
}) => [
  if (storeName.isNotEmpty) PText(storeName, align: PAlign.center, size: PSize.big, bold: true),
  const PDivider(),
  PText('VENDA BALCÃO${number != null ? ' #$number' : ''}', align: PAlign.center, bold: true),
  if (customerName != null && customerName.isNotEmpty) PText('Cliente: $customerName', size: PSize.small),
  PText('${dateTime(DateTime.now())}${operator != null ? ' · $operator' : ''}', size: PSize.small),
  const PDivider(),
  for (final i in items) ...[
    PRow('${qty(i.quantity)}x ${i.product.name}', brl(i.total)),
    for (final d in cartItemDetails(i)) PText('  $d', size: PSize.small),
  ],
  const PDivider(),
  if (itemsTotal != null && (itemsTotal - total).abs() > 0.005) ...[
    PRow('Subtotal', brl(itemsTotal), size: PSize.small),
    PRow(
      itemsTotal > total ? 'Desconto' : 'Acréscimo',
      '${itemsTotal > total ? '-' : '+'} ${brl((itemsTotal - total).abs())}',
      size: PSize.small,
    ),
  ],
  PRow('TOTAL', brl(total), size: PSize.big, bold: true),
  for (final p in payments) PRow(p.label, brl(p.amount), size: PSize.small),
  if (change > 0.005) PRow('Troco', brl(change), size: PSize.small),
  ..._footer,
];

/// Código que identifica o produto no código de barras da ficha: o código
/// (SKU) do cadastro quando o servidor envia; senão, a posição do item na
/// venda com três dígitos (`001`, `002`…).
String ticketProductCode(CartItem item, int position) {
  final code = item.product.code?.trim() ?? '';
  return code.isNotEmpty ? code : position.toString().padLeft(3, '0');
}

/// Fichas da venda de balcão (evento): UMA ficha por unidade paga, com o nome
/// do produto bem visível e um código de barras com o número da venda seguido
/// do código do produto. Item vendido por peso sai em uma ficha só, com a
/// quantidade escrita.
List<PLine> counterTickets({int? number, required List<CartItem> items, DateTime? when}) {
  final at = when ?? DateTime.now();
  final stamp = dateTime(at).replaceFirst(' ', ' - ');
  final lines = <PLine>[];
  for (final (index, item) in items.indexed) {
    final whole = item.quantity == item.quantity.roundToDouble() && item.quantity >= 1;
    final copies = whole ? item.quantity.toInt() : 1;
    final barcode = '${number ?? ''}${ticketProductCode(item, index + 1)}';
    for (var n = 0; n < copies; n++) {
      lines.addAll([
        const PGap(10),
        PText(number != null ? 'VENDA Nº $number' : 'VENDA BALCÃO', align: PAlign.center, bold: true),
        PText(stamp, align: PAlign.center, size: PSize.small),
        const PGap(6),
        PFit(item.product.name.toUpperCase()),
        if (!whole)
          PText(
            '${qty(item.quantity)} ${item.product.unitOfMeasure ?? ''}'.trim(),
            align: PAlign.center,
            size: PSize.big,
            bold: true,
          ),
        for (final d in cartItemDetails(item)) PText(d, align: PAlign.center, size: PSize.small),
        if (item.notes.isNotEmpty) PText('OBS: ${item.notes}', align: PAlign.center, size: PSize.small, bold: true),
        const PGap(8),
        PBarcode(barcode),
        PText(barcode, align: PAlign.center, size: PSize.small),
        const PCut(),
      ]);
    }
  }
  if (lines.isNotEmpty) lines.add(const PGap(36));
  return lines;
}

/// Resumo curto do fechamento de caixa. A Stone pede para não gerar relatório
/// grande na impressora do POS: só totais.
List<PLine> cashCloseSlip({
  required String storeName,
  String? operator,
  required CashDetail detail,
  required Map<String, double> counted,
  required bool showExpected,
}) {
  final s = detail.summary;
  final countedTotal = counted.values.fold<double>(0, (a, b) => a + b);
  final expectedTotal = s.expectedBreakdown.fold<double>(0, (a, e) => a + (e.total ?? 0));
  return [
    if (storeName.isNotEmpty) PText(storeName, align: PAlign.center, size: PSize.big, bold: true),
    const PDivider(),
    const PText('FECHAMENTO DE CAIXA', align: PAlign.center, bold: true),
    if (operator != null) PText('Operador: $operator', size: PSize.small),
    PText('Abertura: ${dateTimeIso(detail.session.openedAt)}', size: PSize.small),
    PText('Fechamento: ${dateTime(DateTime.now())}', size: PSize.small),
    const PDivider(),
    if (showExpected && detail.session.openingAmount != null)
      PRow('Fundo de troco', brl(detail.session.openingAmount)),
    if (showExpected && s.ordersTotal != null) PRow('Vendas (${s.ordersCount})', brl(s.ordersTotal)),
    const PText('CONTADO', bold: true),
    for (final e in s.expectedBreakdown) PRow(e.label, brl(counted[e.key] ?? 0), size: PSize.small),
    PRow('Total contado', brl(countedTotal), bold: true),
    if (showExpected) ...[
      PRow('Esperado', brl(expectedTotal)),
      PRow('Diferença', brl(countedTotal - expectedTotal), bold: true),
    ],
    const PGap(28),
    const PText('______________________________', align: PAlign.center, size: PSize.small),
    const PText('Assinatura', align: PAlign.center, size: PSize.small),
    const PGap(36),
  ];
}

/// DANFE NFC-e: as linhas vêm prontas do servidor (montadas do XML
/// autorizado); aqui só viram linhas de impressão.
List<PLine> danfeReceipt(FiscalNote note) => [
  for (final l in note.lines)
    if (l.qr)
      PQr(l.text)
    else
      PMono(l.text, columns: note.columns, center: l.center, bold: l.bold, big: l.big),
  const PGap(36),
];
