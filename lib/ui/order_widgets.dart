/// Peças comuns do pedido (cardápio, revisão e venda de balcão): miniatura do
/// produto, linha do carrinho, etiqueta de status do item e os textos que
/// citam a mesa.
library;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../models/models.dart';
import '../print/receipt.dart';
import '../stores/order_draft.dart';
import 'kit.dart';

// ── Redesenho seguro ─────────────────────────────────────────────────────────

/// Redesenha a tela quando um store avisa que mudou, mesmo que o aviso chegue
/// no meio da montagem de OUTRA tela (ex.: a tela da mesa chama
/// `SessionStore.fetch` no `initState` enquanto o cardápio ainda está saindo
/// de cena). Nesse caso o redesenho fica para logo depois do quadro.
mixin StoreRebuild<T extends StatefulWidget> on State<T> {
  /// Use como ouvinte dos stores: `store.addListener(rebuild)`.
  void rebuild() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuild());
      return;
    }
    onStoreChanged();
    setState(() {});
  }

  /// Algo a acertar antes de redesenhar (ex.: copiar um valor para um campo).
  void onStoreChanged() {}
}

// ── Miniatura do produto ─────────────────────────────────────────────────────

/// URL da imagem: o servidor pode mandar caminho relativo (`/storage/…`).
String? resolveImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${app.api.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
}

/// Cores do quadrado de iniciais (produto sem foto), uma por categoria.
const thumbPalette = <Color>[
  Color(0xFF2F3BD6),
  Color(0xFFED2188),
  Color(0xFFF29D0C),
  Color(0xFF7A3CFF),
  Color(0xFF0E7C86),
  Color(0xFF6A1B9A),
  Color(0xFF00A874),
  Color(0xFFB8860B),
];

const _smallWords = {'de', 'da', 'do', 'das', 'dos', 'com', 'e', 'em', 'no', 'na', 'c/'};

/// Iniciais do nome: "Guaraná Antarctica Lata" → "GA"; "Suco de Laranja" →
/// "SL"; "Pudim" → "PU".
String productInitials(String name) {
  final words = name
      .split(RegExp(r'[\s\-]+'))
      .where((w) => w.isNotEmpty && !_smallWords.contains(w.toLowerCase()))
      .where((w) => RegExp(r'^[0-9A-Za-zÀ-ÿ]').hasMatch(w))
      .toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first.substring(0, words.first.length < 2 ? 1 : 2).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Foto do produto; sem foto (ou se ela não carregar), um quadrado com as
/// iniciais, para a lista não ficar com um vazio.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, this.url, required this.name, this.color = C.navy, this.size = 46, this.radius = 10});
  final String? url;
  final String name;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: ExcludeSemantics(
        child: Text(
          productInitials(name),
          textScaler: TextScaler.noScaling,
          style: T.s(size * 0.28, w: T.bold, c: C.white, h: 1.1),
        ),
      ),
    );
    final resolved = resolveImageUrl(url);
    if (resolved == null) return initials;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decodifica no tamanho exibido: economiza memória no terminal.
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, _, _) => initials,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : Container(width: size, height: size, color: C.line),
      ),
    );
  }
}

// ── Linha do carrinho ────────────────────────────────────────────────────────

/// Rótulo curto das escolhas do item ("Calabresa / Mussarela · + Bacon · sem cebola").
String cartItemLabel(CartItem item) => [...cartItemDetails(item), if (item.notes.isNotEmpty) item.notes].join(' · ');

/// "4 ITENS" / "1 ITEM" da etiqueta rosa.
String itemsCountLabel(int count) => count == 1 ? '1 ITEM' : '$count ITENS';

/// Um item do carrinho na revisão do pedido e na venda de balcão: nome,
/// escolhas e observação, contador −/+ (ou o peso) e o valor. "−" até zero
/// remove a linha.
class CartLine extends StatelessWidget {
  const CartLine({super.key, required this.item, required this.cart, this.last = false, this.enabled = true});
  final CartItem item;
  final OrderCart cart;
  final bool last;

  /// `false` enquanto o pedido está sendo enviado.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = cartItemLabel(item);
    final unavailable = app.menu.isUnavailable(item.product.id);
    final free = enabled && !cart.locked;
    final fractional = item.product.allowFractionalQty;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.product.name, style: T.body(w: T.semibold)),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: T.s(12, c: C.sub, h: 1.35),
                    ),
                  if (unavailable)
                    Text(
                      'Indisponível no momento',
                      style: T.s(12, w: T.semibold, c: C.orangeText, h: 1.35),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (fractional) ...[
            Text('${qty(item.quantity)} ${item.product.unitOfMeasure ?? 'kg'}', style: T.num(13.5)),
            Semantics(
              button: true,
              label: 'Remover ${item.product.name}',
              child: InkResponse(
                onTap: free ? () => cart.remove(item) : null,
                radius: 22,
                child: Opacity(
                  opacity: free ? 1 : 0.35,
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close, size: 18, color: C.sub)),
                ),
              ),
            ),
          ] else
            QtyStepper(
              value: qty(item.quantity),
              onMinus: free ? () => cart.changeQty(item, -1) : null,
              onPlus: free && item.quantity < 99 ? () => cart.changeQty(item, 1) : null,
            ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Text(brl(item.total), textAlign: TextAlign.right, maxLines: 1, style: T.num(13.5)),
          ),
        ],
      ),
    );
  }
}

// ── Status do item já lançado ────────────────────────────────────────────────

const _statusLabels = {
  'pending': 'Aguardando',
  'preparing': 'Preparando',
  'ready': 'Pronto',
  'delivered': 'Entregue',
  'canceled': 'Cancelado',
};

/// O status que o app mostra para um item da mesa.
String itemStatusLabel(String status) => _statusLabels[status] ?? status;

/// Etiqueta de status do item no layout novo.
class ItemStatusTag extends StatelessWidget {
  const ItemStatusTag(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'pending' => (const Color(0xFFFFF3DC), const Color(0xFF9A5D00)),
      'preparing' => (C.sky100, C.sky700),
      'ready' => (C.greenSoft, C.greenText),
      'canceled' => (C.red100, C.cancel),
      _ => (const Color(0xFFECEBF8), const Color(0xFF4C4E7A)),
    };
    return Tag(itemStatusLabel(status).toLowerCase(), bg: bg, fg: fg);
  }
}

// ── Textos que citam a mesa ──────────────────────────────────────────────────

/// Como citar a mesa no meio de uma frase: "Mesa 7" → "mesa 7"; "12" →
/// "mesa 12"; "Comanda 101" → "comanda 101". Outros nomes: `null`.
String? _tableRef(String title) {
  final t = title.trim();
  if (RegExp(r'^\d+$').hasMatch(t)) return 'mesa $t';
  final m = RegExp(r'^(mesa|comanda)\s+(.+)$', caseSensitive: false).firstMatch(t);
  return m == null ? null : '${m.group(1)!.toLowerCase()} ${m.group(2)}';
}

/// "4 itens da mesa 7" / "1 item da comanda 101" / "2 itens · Varanda".
String sentItemsText(int count, String tableTitle) {
  final items = count == 1 ? '1 item' : '$count itens';
  final ref = _tableRef(tableTitle);
  return ref == null ? '$items · $tableTitle' : '$items da $ref';
}

/// "Ficar na mesa 7" / "Ficar em Varanda".
String stayOnTableText(String tableTitle) {
  final ref = _tableRef(tableTitle);
  return ref == null ? 'Ficar em $tableTitle' : 'Ficar na $ref';
}
