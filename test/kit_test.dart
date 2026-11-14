import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/ui/kit.dart';

Future<void> _pump(WidgetTester tester, Widget home, {double textScale = 1.0}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  testWidgets('barra trio: três botões de largura e altura iguais, sem estouro na fonte máxima', (tester) async {
    await _pump(
      tester,
      Scaffold(
        bottomNavigationBar: BottomBar.trio(
          Btn('+ Itens', kind: BtnKind.green, onTap: () {}),
          Btn('Pedir conta', kind: BtnKind.navy, onTap: () {}),
          Btn('Receber conta', kind: BtnKind.magenta, onTap: () {}),
        ),
      ),
      textScale: 1.15,
    );
    final sizes = tester.widgetList(find.byType(Btn)).map((w) => tester.getSize(find.byWidget(w))).toSet();
    expect(sizes, hasLength(1));
    expect(sizes.single.height, BottomBar.buttonHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barra duo: principal com o dobro da largura do secundário; botão com contador e total', (tester) async {
    await _pump(
      tester,
      Scaffold(
        bottomNavigationBar: BottomBar.duo(
          Btn('Cancelar', kind: BtnKind.secondary, onTap: () {}),
          CountBtn(count: 3, label: 'Revisar pedido', total: 1234.5, onTap: () {}),
        ),
      ),
      textScale: 1.15,
    );
    final secondary = tester.getSize(find.byType(Btn));
    final primary = tester.getSize(find.byType(CountBtn));
    expect(primary.width, closeTo(secondary.width * 2, 0.01));
    expect(primary.height, secondary.height);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Revisar pedido'), findsOneWidget);
    expect(find.text('R\$ 1.234,50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('botão desabilitado não dispara e o contador −/+ tem área de toque de 44 px', (tester) async {
    var taps = 0;
    var value = 1;
    await _pump(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              const Btn('Enviar'),
              CountBtn(count: 0, label: 'Revisar pedido', total: 0, onTap: null),
              QtyStepper(
                value: '$value',
                onMinus: value > 1 ? () => setState(() => value--) : null,
                onPlus: () => setState(() {
                  value++;
                  taps++;
                }),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Enviar'));
    await tester.tap(find.text('Revisar pedido'));
    expect(taps, 0);

    final plus = find.bySemanticsLabel('Mais');
    expect(tester.getSize(plus).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(plus);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Menos'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    // No mínimo, o "−" fica desabilitado.
    await tester.tap(find.bySemanticsLabel('Menos'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('janela por baixo: título, subtítulo e ✕ que fecha; sem ✕ quando não pode ser dispensada', (
    tester,
  ) async {
    late BuildContext ctx;
    await _pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    showSheet<void>(
      ctx,
      (_) => const SheetBody(title: 'Sangria', subtitle: 'Retirada de dinheiro.', children: [Text('corpo')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sangria'), findsOneWidget);
    expect(find.text('Retirada de dinheiro.'), findsOneWidget);
    expect(find.bySemanticsLabel('Fechar'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Sangria'), findsNothing);

    // Tocar no fundo escurecido fecha; tocar dentro da folha (fora de botão) não.
    var taps = 0;
    showSheet<void>(
      ctx,
      (_) => SheetBody(title: 'Sangria', children: [const Text('corpo'), Btn('Confirmar', onTap: () => taps++)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('corpo'));
    await tester.pumpAndSettle();
    expect(find.text('Sangria'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('Sangria'), findsOneWidget);
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    expect(find.text('Sangria'), findsNothing);

    showSheet<void>(
      ctx,
      (c) => SheetBody(
        title: 'Receber venda',
        children: const [Text('corpo')],
        footer: Btn('Voltar', onTap: () => Navigator.pop(c)),
      ),
      dismissible: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Receber venda'), findsOneWidget);
    expect(find.bySemanticsLabel('Fechar'), findsNothing);
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    expect(find.text('Receber venda'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Receber venda'), findsNothing);
  });

  testWidgets('aviso (toast) aparece acima da barra inferior e some em 2 s', (tester) async {
    late BuildContext ctx;
    await _pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          },
        ),
        bottomNavigationBar: MainTabBar(current: MainTab.mesas, onTap: (_) {}),
      ),
    );
    toast(ctx, 'Mesa 99 não existe neste salão');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mesa 99 não existe neste salão'), findsOneWidget);
    final bar = tester.getRect(find.byType(MainTabBar));
    expect(tester.getRect(find.byType(SnackBar)).bottom, lessThanOrEqualTo(bar.top));
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();
    expect(find.text('Mesa 99 não existe neste salão'), findsNothing);
  });

  testWidgets('menu inferior: 4 abas com nome, a ativa em magenta, cada uma com 44 px ou mais de toque', (
    tester,
  ) async {
    MainTab? tapped;
    await _pump(
      tester,
      Scaffold(
        bottomNavigationBar: MainTabBar(current: MainTab.caixa, onTap: (t) => tapped = t),
      ),
    );
    for (final (label, tab) in const [
      ('Mesas', MainTab.mesas),
      ('Balcão', MainTab.balcao),
      ('Caixa', MainTab.caixa),
      ('Mais', MainTab.mais),
    ]) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style!.color, tab == MainTab.caixa ? C.magenta : C.sub);
      expect(
        tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell))).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text(label));
      expect(tapped, tab);
    }
  });

  testWidgets('topo navy: título 17 semibold, subtítulo, voltar e botão com nome', (tester) async {
    var back = 0;
    await _pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            AppHeader(
              title: 'Caixa',
              subtitle: 'Bar do Zé',
              onBack: () => back++,
              actions: [
                HeaderButton.text('Atualizar', onTap: () {}),
                HeaderButton(icon: Icons.notifications_none, badge: 5, tooltip: 'Notificações', onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Caixa'));
    expect(title.style!.fontSize, 17);
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(find.text('Bar do Zé'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    for (final b in tester.widgetList(find.byType(HeaderButton))) {
      expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(44));
    }
    await tester.tap(find.bySemanticsLabel('Voltar'));
    expect(back, 1);
  });
}
