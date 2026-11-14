import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../stores/tables.dart';
import 'kit.dart';
import 'table_status.dart';

/// Largura ÷ altura do card de mesa. É FIXA: todo card da grade tem o mesmo
/// tamanho, derivado só da largura da tela, e o conteúdo é que se adapta.
/// Com 1,0 cabem 24 mesas (6 linhas de 4) em 390 × 844 mesmo com a barra de
/// status do aparelho.
const tableCardAspect = 1.0;

/// Colunas e espaçamento da grade do mapa.
const tableGridColumns = 4;
const tableGridGap = 8.0;

/// Texto grande do card: o número da mesa. Só aparece o título inteiro quando
/// ele foi personalizado (ex.: "Mesa VIP 12"); "Mesa 12" e "Comanda 101"
/// viram "12" e "101".
String tableCardTitle(DiningTable t) {
  final key = tableNumberKey(t);
  final label = t.label?.trim();
  if (label == null || label.isEmpty) return key;
  final f = fold(label);
  final k = fold(key);
  if (f == k || f == 'mesa $k' || f == 'comanda $k') return key;
  return label;
}

/// Valor da conta como no card: sem espaço depois do `R$` ("R$110,00").
String tableCardMoney(num value) => brl(value).replaceFirst('R\$ ', 'R\$');

/// Nome mostrado no card: o cliente, se houver; senão quem abriu a mesa.
String? tableCardName(DiningTable t) {
  final s = t.session;
  if (s == null) return null;
  final customer = s.customerName?.trim();
  if (customer != null && customer.isNotEmpty) return customer;
  final opener = s.openedByName?.trim();
  return (opener != null && opener.isNotEmpty) ? opener : null;
}

/// Frase lida pelo leitor de tela (e usada nos testes), já que o card não
/// escreve o status: "Mesa 5, fechando, Wanderson, R$ 108,90".
String tableCardSemantics(DiningTable t, TableFilter group) {
  final title = tableCardTitle(t);
  final name = title == tableNumberKey(t) ? '${t.isComanda ? 'Comanda' : 'Mesa'} $title' : title;
  final s = t.session;
  return [
    name,
    tableGroupStyle(group).label.toLowerCase(),
    ?tableCardName(t),
    if (s != null) brl(s.total),
    if (t.pendingCalls > 0) t.pendingCalls == 1 ? 'chamado pendente' : '${t.pendingCalls} chamados pendentes',
    if (t.hasUnassignedItems) 'itens sem comanda',
  ].join(', ');
}

/// Card de mesa do mapa (`.mesa` do protótipo): número grande em cima e, em
/// baixo, "livre" ou duas linhas pequenas (nome e valor da conta). O status
/// se lê só pela cor do fundo.
///
/// O card ocupa EXATAMENTE o espaço que a grade dá. Nada aqui dentro muda o
/// tamanho: os textos têm uma linha, cortam com reticências (o valor encolhe)
/// e os selos de chamado e "sem comanda" ficam sobrepostos no canto.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table, required this.group, this.onTap});
  final DiningTable table;

  /// Grupo de cor: [tableGroup] da mesa (livre, ocupada, fechando, ociosa…).
  final TableFilter group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = tableGroupStyle(group);
    final s = table.session;
    final title = tableCardTitle(table);
    final name = tableCardName(table);

    return LayoutBuilder(
      builder: (context, box) {
        // Tudo proporcional à largura do card (84,5 px num celular de 390).
        final k = (box.maxWidth / 84.5).clamp(0.8, 1.7);
        final small = TextStyle(
          fontSize: 10.5 * k,
          fontWeight: FontWeight.w600,
          color: st.text.withValues(alpha: 0.95),
          height: 1.25,
          letterSpacing: 0,
          fontFeatures: tabularFigures,
        );
        final titleSize = switch (title.length) {
          <= 3 => 20.0,
          <= 5 => 16.0,
          _ => 12.5,
        };
        final hasBadge = table.pendingCalls > 0;

        return Semantics(
          button: true,
          label: tableCardSemantics(table, group),
          excludeSemantics: true,
          child: Tap(
            onTap: onTap,
            color: st.bg,
            radius: 14 * k,
            splash: Colors.white24,
            child: SizedBox.expand(
              // Stack: os blocos se sobrepõem se faltar espaço, mas nunca
              // estouram nem empurram o tamanho do card.
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 9 * k,
                    top: 8 * k,
                    right: (hasBadge ? 30 : 8) * k,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize * k,
                        fontWeight: FontWeight.w700,
                        color: st.text,
                        height: 1.05,
                        letterSpacing: 0,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9 * k,
                    right: 8 * k,
                    bottom: 8 * k,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s == null)
                          Text(
                            st.label.toLowerCase(),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          )
                        else ...[
                          if (name != null)
                            Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: small),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(tableCardMoney(s.total), maxLines: 1, softWrap: false, style: small),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasBadge)
                    Positioned(
                      top: 6 * k,
                      right: 6 * k,
                      child: _CallBadge(count: table.pendingCalls, k: k),
                    ),
                  if (table.hasUnassignedItems)
                    Positioned(
                      top: 32 * k,
                      left: 6 * k,
                      right: 6 * k,
                      child: Align(
                        alignment: Alignment.centerRight,
                        // Encolhe em vez de sair do card se a fonte for larga.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 4 * k, vertical: 1 * k),
                            decoration: BoxDecoration(
                              color: const Color(0xEBFFFFFF),
                              borderRadius: BorderRadius.circular(4 * k),
                            ),
                            child: Text(
                              'sem comanda',
                              maxLines: 1,
                              softWrap: false,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 8 * k,
                                fontWeight: FontWeight.w700,
                                color: C.cancel,
                                height: 1.2,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Selo de chamado pendente (sino), discreto, no canto do card.
class _CallBadge extends StatelessWidget {
  const _CallBadge({required this.count, required this.k});
  final int count;
  final double k;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 4 * k, vertical: 2.5 * k),
    decoration: BoxDecoration(color: const Color(0xEBFFFFFF), borderRadius: BorderRadius.circular(10 * k)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notifications_active, size: 12 * k, color: C.ink),
        if (count > 1)
          Padding(
            padding: EdgeInsets.only(left: 1.5 * k),
            child: Text(
              count > 9 ? '9+' : '$count',
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 9.5 * k,
                fontWeight: FontWeight.w700,
                color: C.ink,
                height: 1.1,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Grade do mapa de mesas: 4 colunas, espaço de 8 px e cards de tamanho fixo
/// ([tableCardAspect]). Usa a grade do Flutter, que dá a TODAS as células a
/// mesma largura e altura, sem olhar o conteúdo.
class TableGrid extends StatelessWidget {
  const TableGrid({
    super.key,
    required this.tables,
    required this.idleLimitMinutes,
    required this.now,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(14, 6, 14, 12),
  });
  final List<DiningTable> tables;
  final int idleLimitMinutes;
  final DateTime now;
  final ValueChanged<DiningTable> onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: padding,
    physics: const AlwaysScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: tableGridColumns,
      mainAxisSpacing: tableGridGap,
      crossAxisSpacing: tableGridGap,
      childAspectRatio: tableCardAspect,
    ),
    itemCount: tables.length,
    itemBuilder: (context, i) {
      final t = tables[i];
      return TableCard(
        key: ValueKey(t.id),
        table: t,
        group: tableGroup(t, idleLimitMinutes, now),
        onTap: () => onTap(t),
      );
    },
  );
}
