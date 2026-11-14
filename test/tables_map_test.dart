import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/models/models.dart';
import 'package:mobizweb_pos/stores/tables.dart';
import 'package:mobizweb_pos/ui/table_card.dart';

final _now = DateTime.parse('2026-11-14T15:00:00Z');

DiningTable _table(
  String number, {
  String status = 'available',
  String? label,
  bool comanda = false,
  String? customer,
  String? openedBy,
  double total = 0,
  int idleFor = 1,
  int calls = 0,
  bool unassigned = false,
  String? area = 'Salão',
}) {
  final hasSession = status == 'occupied' || status == 'closing';
  return DiningTable(
    id: 'id-$number-${comanda ? 'c' : 'm'}',
    number: number,
    label: label ?? '${comanda ? 'Comanda' : 'Mesa'} $number',
    status: status,
    isComanda: comanda,
    areaName: area,
    pendingCalls: calls,
    hasUnassignedItems: unassigned,
    session: !hasSession
        ? null
        : TableSessionSummary(
            id: 'sess-$number',
            status: status == 'closing' ? 'closing' : 'open',
            openedAt: _now.subtract(const Duration(hours: 2)).toIso8601String(),
            lastActivityAt: _now.subtract(Duration(minutes: idleFor)).toIso8601String(),
            guestCount: 3,
            customerName: customer,
            openedByName: openedBy,
            total: total,
          ),
  );
}

void main() {
  group('contagem dos chips de filtro', () {
    final tables = [
      _table('1'),
      _table('2'),
      _table('3', status: 'occupied', calls: 2),
      _table('4', status: 'occupied', idleFor: 48),
      _table('5', status: 'closing', idleFor: 90, calls: 1),
      _table('6', status: 'reserved'),
    ];

    test('grupos exclusivos somam o total; ociosa sai de ocupadas; pendentes conta mesas com chamado', () {
      final c = countTablesByFilter(tables, 30, _now);
      expect(c[TableFilter.all], 6);
      expect(c[TableFilter.available], 2);
      expect(c[TableFilter.occupied], 1);
      expect(c[TableFilter.idle], 1);
      // "Fechando" nunca vira ociosa, mesmo parada há muito tempo.
      expect(c[TableFilter.closing], 1);
      expect(c[TableFilter.reserved], 1);
      expect(c[TableFilter.pending], 2);
      final groups = [
        TableFilter.available,
        TableFilter.occupied,
        TableFilter.idle,
        TableFilter.closing,
        TableFilter.reserved,
      ];
      expect(groups.fold<int>(0, (a, g) => a + c[g]!), c[TableFilter.all]);
    });

    test('com o alerta de ociosidade desligado (0) ninguém é ociosa', () {
      final c = countTablesByFilter(tables, 0, _now);
      expect(c[TableFilter.idle], 0);
      expect(c[TableFilter.occupied], 2);
    });

    test('o filtro mostra exatamente as mesas contadas no chip', () {
      final c = countTablesByFilter(tables, 30, _now);
      for (final f in TableFilter.values) {
        expect(tables.where((t) => tableMatchesFilter(t, f, 30, _now)).length, c[f], reason: '$f');
      }
    });
  });

  group('botão Entrar', () {
    final tables = [
      _table('1'),
      _table('10'),
      _table('12', status: 'occupied'),
      _table('112'),
      _table('7', label: 'Mesa VIP 7'),
      _table('101', comanda: true),
      _table('12', comanda: true),
    ];

    test('abre a mesa de número exato, não uma parecida', () {
      expect(findTableForEntry(tables, '12')?.id, 'id-12-m');
      expect(findTableForEntry(tables, ' 1 ')?.id, 'id-1-m');
      expect(findTableForEntry(tables, 'mesa 10')?.id, 'id-10-m');
      expect(findTableForEntry(tables, 'MESA VIP 7')?.id, 'id-7-m');
    });

    test('acha comanda pelo número e respeita a aba aberta no empate', () {
      expect(findTableForEntry(tables, '101')?.id, 'id-101-c');
      expect(findTableForEntry(tables, 'comanda 101')?.id, 'id-101-c');
      expect(findTableForEntry(tables, '12', preferComanda: true)?.id, 'id-12-c');
    });

    test('número inexistente ou vazio devolve nulo', () {
      expect(findTableForEntry(tables, '99'), isNull);
      expect(findTableForEntry(tables, '11'), isNull);
      expect(findTableForEntry(tables, '   '), isNull);
    });

    test('a busca enquanto digita continua por pedaço do título ou do número', () {
      expect(tables.where((t) => tableMatchesQuery(t, '1')).length, 6);
      expect(tables.where((t) => tableMatchesQuery(t, 'vip')).single.id, 'id-7-m');
      expect(tables.where((t) => tableMatchesQuery(t, '')).length, tables.length);
    });
  });

  group('card de mesa', () {
    final tables = [
      _table('1'),
      _table(
        '2',
        status: 'occupied',
        customer: 'Maria Aparecida de Souza Albuquerque',
        openedBy: 'Wanderson',
        total: 12345.67,
      ),
      _table('3', status: 'occupied', openedBy: 'Wanderson', total: 110, calls: 3, unassigned: true),
      _table('5', status: 'closing', openedBy: 'Jefferson', total: 108.9, idleFor: 72),
      _table('9', status: 'occupied', openedBy: 'Ana', total: 13.2, idleFor: 48),
      _table('20', status: 'reserved'),
      _table('12', label: 'Mesa VIP 12', status: 'occupied', total: 59.4, calls: 1),
      _table('101', comanda: true, status: 'occupied', customer: 'João', total: 999999.99, unassigned: true),
    ];

    Future<void> pumpGrid(WidgetTester tester, {required Size size, double textScale = 1.0}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: TableGrid(tables: tables, idleLimitMinutes: 30, now: _now, onTap: (_) {}),
            ),
          ),
        ),
      );
    }

    testWidgets('todos os cards têm o mesmo tamanho, seja qual for o conteúdo, sem estouro na fonte máxima', (
      tester,
    ) async {
      for (final size in const [Size(390, 844), Size(360, 640), Size(320, 569)]) {
        for (final scale in const [1.0, 1.15]) {
          await pumpGrid(tester, size: size, textScale: scale);
          expect(tester.takeException(), isNull, reason: '$size x$scale');
          final sizes = tester
              .widgetList<TableCard>(find.byType(TableCard))
              .map((w) => tester.getSize(find.byWidget(w)))
              .toSet();
          expect(find.byType(TableCard), findsNWidgets(tables.length));
          expect(sizes, hasLength(1), reason: 'tamanhos diferentes em $size x$scale: $sizes');
          // Tamanho derivado só da largura da tela: (largura − margens − 3 espaços) ÷ 4, proporção fixa.
          final width = (size.width - 28 - 3 * tableGridGap) / tableGridColumns;
          expect(sizes.single.width, closeTo(width, 0.01));
          expect(sizes.single.height, closeTo(width / tableCardAspect, 0.01));
        }
      }
    });

    testWidgets('nenhum texto do card quebra em duas linhas nem sai do card', (tester) async {
      await pumpGrid(tester, size: const Size(390, 844), textScale: 1.15);
      for (final card in tester.widgetList<TableCard>(find.byType(TableCard))) {
        final box = tester.getRect(find.byWidget(card));
        final texts = find.descendant(of: find.byWidget(card), matching: find.byType(Text));
        for (final e in texts.evaluate()) {
          final r = tester.getRect(find.byWidget(e.widget));
          expect((e.widget as Text).maxLines, 1);
          expect(
            r.left >= box.left - 0.01 && r.right <= box.right + 0.01,
            isTrue,
            reason: '${(e.widget as Text).data} fora do card ${card.table.number}',
          );
          expect(
            r.top >= box.top - 0.01 && r.bottom <= box.bottom + 0.01,
            isTrue,
            reason: '${(e.widget as Text).data} fora do card ${card.table.number}',
          );
        }
      }
    });

    testWidgets(
      'livre mostra "livre"; ocupada mostra o cliente ou quem abriu e o valor; sem área nem rótulo de status',
      (tester) async {
        await pumpGrid(tester, size: const Size(390, 844));
        Finder inCard(String number, {bool comanda = false}) =>
            find.byWidgetPredicate((w) => w is TableCard && w.table.number == number && w.table.isComanda == comanda);
        Iterable<String?> textsOf(Finder card) =>
            tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text))).map((t) => t.data);

        expect(textsOf(inCard('1')), ['1', 'livre']);
        // Cliente informado ganha de quem abriu.
        expect(textsOf(inCard('2')), ['2', 'Maria Aparecida de Souza Albuquerque', 'R\$12.345,67']);
        // Sem cliente: quem abriu a mesa. Selos: sino com contagem e "sem comanda".
        expect(textsOf(inCard('3')), ['3', 'Wanderson', 'R\$110,00', '3', 'sem comanda']);
        expect(textsOf(inCard('5')), ['5', 'Jefferson', 'R\$108,90']);
        // Ociosa: só a cor muda; nada de "Ociosa · N min".
        expect(textsOf(inCard('9')), ['9', 'Ana', 'R\$13,20']);
        // Título personalizado aparece inteiro (reduzido); o padrão vira só o número.
        expect(textsOf(inCard('12')), ['Mesa VIP 12', 'R\$59,40']);
        expect(textsOf(inCard('101', comanda: true)), ['101', 'João', 'R\$999.999,99', 'sem comanda']);

        for (final gone in ['Salão', 'Ocupada', 'Livre', 'Fechando', 'Ociosa', 'Reservada', '3 pessoa(s)']) {
          expect(find.text(gone), findsNothing, reason: gone);
        }
        expect(find.textContaining('min'), findsNothing);
        expect(find.byType(Divider), findsNothing);
      },
    );

    testWidgets('a cor de fundo segue o status e o rótulo de acessibilidade diz o status por extenso', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpGrid(tester, size: const Size(390, 844));
      expect(find.bySemanticsLabel('Mesa 1, livre'), findsOneWidget);
      expect(find.bySemanticsLabel('Mesa 5, fechando, Jefferson, R\$ 108,90'), findsOneWidget);
      expect(find.bySemanticsLabel('Mesa 9, ociosa, Ana, R\$ 13,20'), findsOneWidget);
      expect(find.bySemanticsLabel('Mesa 20, reservada'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Mesa 3, ocupada, Wanderson, R\$ 110,00, 3 chamados pendentes, itens sem comanda'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Mesa VIP 12, ocupada, R\$ 59,40, chamado pendente'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('24 mesas cabem sem rolar em 390 × 844, mesmo com as barras do aparelho', (tester) async {
      // Espaço que sobra para a grade: tela menos barra de status (34), topo
      // (114), chips (48), menu inferior (61) e barra de gestos (14).
      const viewport = Size(390, 844 - 34 - 114 - 48 - 61 - 14);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final many = [for (var i = 1; i <= 24; i++) _table('$i')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableGrid(tables: many, idleLimitMinutes: 0, now: _now, onTap: (_) {}),
          ),
        ),
      );
      final last = tester.getRect(find.byWidgetPredicate((w) => w is TableCard && w.table.number == '24'));
      expect(last.bottom, lessThanOrEqualTo(viewport.height));
      expect(find.byType(TableCard), findsNWidgets(24));
    });
  });
}
