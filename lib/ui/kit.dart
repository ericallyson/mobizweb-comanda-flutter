/// Kit visual do app: os blocos do layout novo do garçom (seção 3 de
/// `docs/layout-novo.md`).
///
/// Para montar uma tela nova:
///  - topo navy: [AppHeader] (+ [HeaderButton]);
///  - corpo: fundo `C.bg`, [SectionLabel], [CardBox], [HeroCard], [MenuRow];
///  - rodapé fixo: [BottomBar.trio] / [BottomBar.duo] com [Btn] ou [CountBtn]
///    no `bottomNavigationBar` do `Scaffold` (o aviso de [toast] aparece
///    logo acima);
///  - menu inferior das telas raiz: [MainTabBar];
///  - quantidade: [QtyStepper]; janela por baixo: [showSheet] + [SheetBody];
///  - valores: `T.num(...)` (algarismos tabulares).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/theme.dart';

export '../core/format.dart';
export '../core/theme.dart';

// ── Toque ────────────────────────────────────────────────────────────────────

/// Área tocável com realce (o `active:bg-…` do Tailwind).
class Tap extends StatelessWidget {
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.transparent,
    this.radius = 12,
    this.border,
    this.padding,
    this.splash,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final BorderSide? border;
  final EdgeInsetsGeometry? padding;
  final Color? splash;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ?? BorderSide.none,
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: splash ?? Colors.black.withValues(alpha: 0.08),
        highlightColor: splash ?? Colors.black.withValues(alpha: 0.06),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

// ── Botões ───────────────────────────────────────────────────────────────────

/// Cores de botão do layout novo. Use os nomes novos nas telas novas:
/// `magenta` (ação principal), `navy`, `green` ("+ Itens", "Suprimento"),
/// `orange` ("Sangria") e `secondary` (contorno). Os nomes antigos continuam
/// valendo para as telas que ainda não foram refeitas.
enum BtnKind {
  primary,
  accent,
  outline,
  danger,
  dangerSoft,
  success,
  warn;

  /// Ação principal da tela (Revisar, Enviar para cozinha, Receber).
  static const magenta = BtnKind.accent;

  /// "Pedir conta", "Fechar caixa", "Abrir caixa".
  static const navy = BtnKind.primary;

  /// "+ Itens", "Suprimento".
  static const green = BtnKind.success;

  /// "Sangria".
  static const orange = BtnKind.warn;

  /// Secundário: fundo branco com contorno ("Cancelar", "Ver detalhes").
  static const secondary = BtnKind.outline;
}

/// Marca que os botões abaixo estão numa [BottomBar] (fonte 13,5 e menos
/// respiro lateral, para caber três lado a lado em 360 px).
class _BarScope extends InheritedWidget {
  const _BarScope({required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BarScope>() != null;

  @override
  bool updateShouldNotify(_BarScope oldWidget) => false;
}

/// Botão padrão: raio 14, altura mínima de 46 px (44 no `dense`), texto 14
/// em negrito. A cor vem de [BtnKind]:
///
/// ```dart
/// Btn('Receber conta', kind: BtnKind.magenta, onTap: _receive)
/// Btn('Cancelar', kind: BtnKind.secondary, onTap: _cancel)
/// ```
class Btn extends StatelessWidget {
  const Btn(
    this.label, {
    super.key,
    this.onTap,
    this.kind = BtnKind.primary,
    this.loading = false,
    this.dense = false,
    this.icon,
    this.bold = false,
  });

  final String label;

  /// `null` desabilita (o botão fica apagado).
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool loading;

  /// Versão compacta (texto 12) para linhas de lista.
  final bool dense;
  final IconData? icon;

  /// Mantido por compatibilidade: o texto já é sempre em negrito.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (C.navy, C.white, null),
      BtnKind.accent => (C.magenta, C.white, null),
      BtnKind.outline => (C.white, C.ink, const BorderSide(color: C.line, width: 1.5)),
      BtnKind.danger => (C.red500, C.white, null),
      BtnKind.dangerSoft => (C.red50, C.cancel, null),
      BtnKind.success => (C.green, C.white, null),
      BtnKind.warn => (C.orange, C.white, null),
    };
    final enabled = onTap != null && !loading;
    final inBar = _BarScope.of(context);
    final size = dense ? 12.0 : (inBar ? 13.5 : 14.0);
    return Opacity(
      opacity: enabled ? 1 : (loading ? 0.7 : 0.4),
      child: Tap(
        onTap: enabled ? onTap : null,
        color: bg,
        border: border,
        radius: 14,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: dense ? 44 : 46),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 6 : (inBar ? 4 : 12), vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                  )
                else if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(icon, size: dense ? 16 : 18, color: fg),
                  ),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(size, w: T.bold, c: fg, h: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão principal com contador e total: `[2] Revisar pedido      R$ 34,00`.
/// É o botão da direita da [BottomBar.duo] no cardápio e no balcão. Sem
/// `count` o contador some (`Receber      R$ 23,00`); `icon` entra no lugar
/// dele (`➤ Enviar para cozinha      R$ 92,00`).
///
/// ```dart
/// CountBtn(count: cart.length, label: 'Revisar pedido', total: total, onTap: cart.isEmpty ? null : _review)
/// CountBtn(icon: Icons.send_outlined, label: 'Enviar para cozinha', total: total, onTap: _send)
/// ```
class CountBtn extends StatelessWidget {
  const CountBtn({
    super.key,
    this.count,
    this.icon,
    required this.label,
    required this.total,
    this.onTap,
    this.loading = false,
    this.kind = BtnKind.accent,
  });

  /// Quantidade no selo translúcido; `null` = sem selo.
  final int? count;

  /// Ícone à esquerda do nome (usado quando não há `count`).
  final IconData? icon;
  final String label;
  final num total;

  /// `null` desabilita (ex.: pedido sem itens).
  final VoidCallback? onTap;
  final bool loading;
  final BtnKind kind;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final bg = switch (kind) {
      BtnKind.primary => C.navy,
      BtnKind.success => C.green,
      BtnKind.warn => C.orange,
      _ => C.magenta,
    };
    return Opacity(
      opacity: enabled ? 1 : (loading ? 0.7 : 0.4),
      child: LayoutBuilder(
        builder: (context, box) => Tap(
          onTap: enabled ? onTap : null,
          color: bg,
          radius: 14,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  if (loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: C.white),
                    )
                  else if (count != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(8)),
                      child: Text('$count', style: T.num(12, c: C.white)),
                    )
                  else if (icon != null)
                    Icon(icon, size: 18, color: C.white),
                  if (loading || count != null || icon != null) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.s(14, w: T.bold, c: C.white, h: 1.15),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // O total nunca corta: encolhe se passar da metade do botão.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(brl(total), maxLines: 1, style: T.num(14, c: C.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de ações inferior fixa: fundo branco, borda superior e botões de
/// altura igual (46 px). Vai no `bottomNavigationBar` do `Scaffold`.
///
///  - [BottomBar.trio]: três botões de LARGURA IGUAL (mesa aberta);
///  - [BottomBar.duo]: secundário com 1 parte e principal com 2 partes
///    (revisão do pedido, cardápio, venda de balcão).
///
/// ```dart
/// bottomNavigationBar: BottomBar.duo(
///   Btn('+ Itens', kind: BtnKind.green, onTap: _addItems),
///   CountBtn(count: 3, label: 'Enviar para cozinha', total: 58.0, onTap: _send),
/// ),
/// ```
class BottomBar extends StatelessWidget {
  /// Forma livre: um `flex` por botão (padrão: todos iguais).
  const BottomBar({super.key, required this.children, this.flex});

  /// Três botões de largura igual.
  BottomBar.trio(Widget a, Widget b, Widget c, {super.key}) : children = [a, b, c], flex = const [1, 1, 1];

  /// Secundário (1 parte) à esquerda e principal (2 partes) à direita.
  BottomBar.duo(Widget secondary, Widget primary, {super.key}) : children = [secondary, primary], flex = const [1, 2];

  final List<Widget> children;
  final List<int>? flex;

  static const buttonHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottom),
      child: _BarScope(
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                flex: flex != null && i < flex!.length ? flex![i] : 1,
                child: SizedBox(height: buttonHeight, child: children[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dois botões lado a lado (`flex gap-3`), o padrão dos rodapés de modal.
class BtnRow extends StatelessWidget {
  const BtnRow(this.left, this.right, {super.key});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      Expanded(child: right),
    ],
  );
}

/// Botão do topo navy: quadrado translúcido de 36 px (área de toque de 44)
/// com ícone, ou com texto ([HeaderButton.text], ex.: "Atualizar"). `badge`
/// mostra o contador magenta no canto (sino de notificações).
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required IconData this.icon,
    this.onTap,
    this.badge,
    this.tooltip,
    this.spinning = false,
  }) : label = null;

  /// Botão com nome em vez de ícone.
  const HeaderButton.text(String this.label, {super.key, this.onTap, this.spinning = false})
    : icon = null,
      badge = null,
      tooltip = null;

  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final int? badge;
  final String? tooltip;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.white));
    final Widget face = Container(
      height: 36,
      constraints: const BoxConstraints(minWidth: 36),
      padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(10)),
      // Com nome, o botão não muda de largura enquanto carrega: só apaga.
      child: label != null
          ? Opacity(
              opacity: spinning ? 0.45 : 1,
              child: Text(label!, style: T.s(12, w: T.bold, c: C.white, h: 1.2)),
            )
          : (spinning ? spinner : Icon(icon, size: 19, color: C.white)),
    );
    final hasBadge = badge != null && badge! > 0;
    return Semantics(
      button: true,
      label: tooltip == null ? null : (hasBadge ? '$tooltip ($badge)' : tooltip),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: !hasBadge
                  ? face
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        face,
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(color: C.magenta, borderRadius: BorderRadius.circular(9)),
                            alignment: Alignment.center,
                            child: ExcludeSemantics(
                              child: Text(
                                badge! > 99 ? '99+' : '$badge',
                                textScaler: TextScaler.noScaling,
                                style: T.s(10, w: T.bold, c: C.white, h: 1.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cabeçalho ────────────────────────────────────────────────────────────────

/// Topo navy das telas, respeitando a área segura: título 17 semibold,
/// subtítulo, "voltar" à esquerda e botões à direita.
///
///  - `titleWidget` troca o título por um widget (ex.: nome da loja com "▾");
///  - `bottom` entra dentro do navy, abaixo da linha do título (campo de
///    busca do mapa de mesas e do cardápio).
///
/// ```dart
/// AppHeader(title: 'Mesa 7', subtitle: 'Ana · 2 pessoas', onBack: () => Navigator.pop(context),
///   actions: [HeaderButton.text('Conta', onTap: _openBill)])
/// ```
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.subtitleWidget,
    this.titleWidget,
    this.bottom,
  });
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? titleWidget;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(statusBarColor: C.navy),
    child: Material(
      color: C.navy,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 4, bottom: bottom == null ? 10 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // Os botões têm 4 px de folga de toque: 12 + 4 alinha em 16.
              padding: EdgeInsets.only(left: onBack != null ? 12 : 16, right: actions.isEmpty ? 16 : 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    if (onBack != null) ...[
                      HeaderButton(icon: Icons.chevron_left, onTap: onBack, tooltip: 'Voltar'),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          titleWidget ?? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.top),
                          if (subtitleWidget != null)
                            subtitleWidget!
                          else if (subtitle != null && subtitle!.isNotEmpty)
                            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.topSub),
                        ],
                      ),
                    ),
                    for (final a in actions) Padding(padding: const EdgeInsets.only(left: 2), child: a),
                  ],
                ),
              ),
            ),
            if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: bottom),
          ],
        ),
      ),
    ),
  );
}

/// Menu inferior das telas raiz: 4 abas com ícone E nome. A aba ativa fica em
/// magenta. Aparece no mapa de mesas, no Caixa e em Mais.
enum MainTab { mesas, balcao, caixa, mais }

class MainTabBar extends StatelessWidget {
  const MainTabBar({super.key, required this.current, required this.onTap, this.badges = const {}});

  final MainTab current;
  final ValueChanged<MainTab> onTap;

  /// Contador opcional por aba (ex.: notificações em "Mais").
  final Map<MainTab, int> badges;

  static const _tabs = <(MainTab, String, IconData)>[
    (MainTab.mesas, 'Mesas', Icons.grid_view_outlined),
    (MainTab.balcao, 'Balcão', Icons.shopping_bag_outlined),
    (MainTab.caixa, 'Caixa', Icons.credit_card_outlined),
    (MainTab.mais, 'Mais', Icons.menu),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: C.white,
      shape: const Border(top: BorderSide(color: C.line)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, 5, 6, 6 + bottom),
        child: Row(
          children: [
            for (final (tab, label, icon) in _tabs)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: tab == current,
                  child: InkWell(
                    onTap: () => onTap(tab),
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 50),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(icon, size: 23, color: tab == current ? C.magenta : C.sub),
                              if ((badges[tab] ?? 0) > 0)
                                Positioned(
                                  top: -4,
                                  right: -9,
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(color: C.magenta, borderRadius: BorderRadius.circular(8)),
                                    alignment: Alignment.center,
                                    child: ExcludeSemantics(
                                      child: Text(
                                        '${badges[tab]}',
                                        textScaler: TextScaler.noScaling,
                                        style: T.s(10, w: T.bold, c: C.white, h: 1.2),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            maxLines: 1,
                            style: T.s(11, w: T.semibold, c: tab == current ? C.magenta : C.sub, h: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Campos ───────────────────────────────────────────────────────────────────

/// Aparência dos campos: fundo branco, contorno de 1,5 px na cor de linha e
/// raio 12; o contorno ganha a cor `focus` quando o campo está ativo.
InputDecoration fieldDecoration({String? hint, Color fill = C.white, Color focus = C.navy, Widget? suffix}) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: 1.5),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: T.sm(c: C.zinc400),
    isDense: true,
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: b(C.line),
    enabledBorder: b(C.line),
    disabledBorder: b(C.line),
    focusedBorder: b(focus),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
  );
}

/// Rótulo de seção (10,5 px, maiúsculas) + campo.
class Field extends StatelessWidget {
  const Field({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.obscure = false,
    this.maxLength,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.formatters,
    this.action,
    this.focus = C.navy,
    this.fill = C.white,
    this.large = false,
    this.maxLines = 1,
    this.autofill,
  });

  final String? label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool obscure;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final List<TextInputFormatter>? formatters;
  final TextInputAction? action;
  final Color focus;
  final Color fill;
  final bool large;
  final int maxLines;
  final Iterable<String>? autofill;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null) ...[Text(label!.toUpperCase(), style: T.section), const SizedBox(height: 6)],
      TextField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        autofocus: autofocus,
        enabled: enabled,
        maxLines: maxLines,
        inputFormatters: [
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ...?formatters,
        ],
        textInputAction: action,
        autofillHints: autofill,
        autocorrect: false,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: large
            ? T.base(w: T.medium, c: enabled ? C.ink : C.zinc400)
            : T.sm(w: T.medium, c: enabled ? C.ink : C.zinc400),
        decoration: fieldDecoration(hint: hint, focus: focus, fill: enabled ? fill : C.bg),
      ),
    ],
  );
}

/// Campo de valor em reais (teclado decimal, aceita vírgula ou ponto).
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    this.label,
    required this.controller,
    this.onChanged,
    this.enabled = true,
    this.focus = C.navy,
    this.autofocus = false,
    this.hint = '0,00',
  });

  final String? label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Color focus;
  final bool autofocus;
  final String hint;

  static final _fmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  @override
  Widget build(BuildContext context) => Field(
    label: label,
    controller: controller,
    hint: hint,
    keyboard: const TextInputType.numberWithOptions(decimal: true),
    formatters: _fmt,
    onChanged: onChanged,
    enabled: enabled,
    focus: focus,
    autofocus: autofocus,
    large: true,
  );
}

/// Bloco "Liberação do gerente" (e-mail + senha do autorizador).
class OverrideFields extends StatelessWidget {
  const OverrideFields({super.key, required this.email, required this.password, this.title = 'Liberação do gerente', this.onChanged});
  final TextEditingController email;
  final TextEditingController password;
  final String title;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: C.zinc50, borderRadius: BorderRadius.circular(8)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.xs(w: T.medium, c: C.zinc600)),
        const SizedBox(height: 8),
        Field(
          controller: email,
          hint: 'E-mail do autorizador',
          keyboard: TextInputType.emailAddress,
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 8),
        Field(controller: password, hint: 'Senha do autorizador', obscure: true, onChanged: (_) => onChanged?.call()),
      ],
    ),
  );
}

// ── Avisos ───────────────────────────────────────────────────────────────────

enum NoteKind { warn, error, info }

/// Faixa de aviso (`bg-amber-50 text-amber-700` / `bg-red-50 text-red-600`).
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.kind = NoteKind.warn, this.center = true, this.onTap, this.radius = 8});
  final String text;
  final NoteKind kind;
  final bool center;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      NoteKind.warn => (C.amber50, C.amber800),
      NoteKind.error => (C.red50, C.red600),
      NoteKind.info => (C.primary50, C.primary700),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Text(text, textAlign: center ? TextAlign.center : TextAlign.start, style: T.xs(w: T.medium, c: fg)),
      ),
    );
  }
}

class ErrText extends StatelessWidget {
  const ErrText(this.text, {super.key, this.center = false});
  final String? text;
  final bool center;

  @override
  Widget build(BuildContext context) => (text == null || text!.isEmpty)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text!, textAlign: center ? TextAlign.center : TextAlign.start, style: T.xs(c: C.red500)),
        );
}

/// Etiqueta arredondada (`rounded-full px-2.5 py-1`).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.size = 12, this.bold = true});
  final String text;
  final Color bg;
  final Color fg;
  final double size;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.s(size, w: bold ? T.bold : T.semibold, c: fg, h: 1.3)),
  );
}

/// Opção de seleção (`rounded-xl border`, ativa = `border-primary-600 bg-primary-50`).
class Choice extends StatelessWidget {
  const Choice(this.label, {super.key, required this.selected, this.onTap, this.solid = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Ativa em navy cheio (painel de configurações) em vez de navy claro.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? (solid ? C.primary600 : C.primary50) : C.white;
    final fg = selected ? (solid ? C.white : C.primary700) : C.zinc600;
    return Tap(
      onTap: onTap,
      color: bg,
      border: BorderSide(color: selected ? C.primary600 : C.zinc200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: T.s(solid ? 14 : 12, w: T.semibold, c: fg, h: 1.3),
        ),
      ),
    );
  }
}

/// Grade de N colunas com altura automática por linha (o `grid grid-cols-N`).
class ColGrid extends StatelessWidget {
  const ColGrid({super.key, required this.cols, required this.children, this.gap = 8});
  final int cols;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, (i + cols).clamp(0, children.length));
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(child: c < slice.length ? slice[c] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Tela cheia de estado (carregando, vazio, erro com "Tentar novamente").
class StateView extends StatelessWidget {
  const StateView({super.key, required this.text, this.icon, this.error = false, this.actionLabel, this.onAction, this.detail});
  final String text;
  final IconData? icon;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 36, color: error ? C.red400 : C.zinc300), const SizedBox(height: 12)],
          Text(text, textAlign: TextAlign.center, style: T.sm(w: T.medium, c: error ? C.red500 : C.zinc500)),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, textAlign: TextAlign.center, style: T.xs(c: C.zinc400)),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: 200, child: Btn(actionLabel ?? 'Tentar novamente', onTap: onAction)),
          ],
        ],
      ),
    ),
  );
}

/// Contador −/+ do layout novo: botões redondos de 32 px (área de toque de
/// 44), "+" magenta cheio e "−" com contorno magenta. `null` em [onMinus] ou
/// [onPlus] desabilita aquele lado.
///
/// ```dart
/// QtyStepper(value: '$qty', onMinus: qty > 1 ? _dec : null, onPlus: _inc)
/// ```
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, this.onMinus, this.onPlus, this.size = 32});
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  /// Diâmetro visível do botão.
  final double size;

  Widget _b({required bool plus, required VoidCallback? onTap}) {
    final slop = size >= 44 ? 0.0 : (44 - size) / 2;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: plus ? 'Mais' : 'Menos',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Padding(
            padding: EdgeInsets.all(slop),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: plus ? C.magenta : C.white,
                border: plus ? null : Border.all(color: C.magenta, width: 1.5),
              ),
              child: Icon(plus ? Icons.add : Icons.remove, size: size * 0.56, color: plus ? C.white : C.magenta),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _b(plus: false, onTap: onMinus),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 16),
        child: Text(value, textAlign: TextAlign.center, style: T.num(14)),
      ),
      _b(plus: true, onTap: onPlus),
    ],
  );
}

/// Linha "rótulo …… valor" dos resumos de conta.
class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.strong = false, this.color});
  final String k;
  final String v;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(k, style: strong ? T.sm(w: T.semibold, c: color ?? C.zinc700) : T.xs(c: color ?? C.zinc500)),
        ),
        Text(v, style: strong ? T.lg(w: T.bold, c: color ?? C.primary700) : T.xs(w: T.medium, c: color ?? C.zinc600)),
      ],
    ),
  );
}

// ── Folhas e diálogos ────────────────────────────────────────────────────────

/// Diz ao [SheetBody] se a folha pode ser fechada pelo operador (✕).
class _SheetScope extends InheritedWidget {
  const _SheetScope({required this.dismissible, required super.child});
  final bool dismissible;

  static bool dismissibleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetScope>()?.dismissible ?? true;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => dismissible != oldWidget.dismissible;
}

/// Janela por baixo (bottom sheet): fundo escurecido, cantos de 22 px no
/// topo, largura máx. 448, rolável e sobe junto com o teclado. O conteúdo
/// normalmente é um [SheetBody]. Fecha pelo ✕, arrastando para baixo ou tocando
/// fora. Com `dismissible: false` a folha só fecha pelos botões do próprio
/// conteúdo (sem ✕, sem arrastar, sem tocar fora).
Future<R?> showSheet<R>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) =>
    showModalBottomSheet<R>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x7305061F),
      // A área transparente acima da folha faz parte dela (a folha pode crescer
      // até 92% da tela), então o toque "fora" é tratado aqui: fecha quando a
      // folha pode ser dispensada.
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: dismissible ? () => Navigator.maybePop(ctx) : null,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 448,
                maxHeight: (MediaQuery.sizeOf(ctx).height - MediaQuery.viewInsetsOf(ctx).bottom) * 0.92,
              ),
              // Toque dentro da folha (em área sem botão) não fecha.
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: C.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: _SheetScope(dismissible: dismissible, child: Builder(builder: builder)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// Corpo padrão de folha: alça cinza, cabeçalho (título, subtítulo e ✕),
/// conteúdo rolável e rodapé fixo. O ✕ só aparece quando há `title` e a folha
/// pode ser fechada (`showSheet(dismissible: true)`); `closable: false` o
/// esconde.
///
/// ```dart
/// showSheet<bool>(context, (c) => SheetBody(
///   title: 'Sangria',
///   subtitle: 'Retirada de dinheiro do caixa.',
///   children: [MoneyField(label: 'Valor (R\$)', controller: _amount)],
///   footer: BtnRow(Btn('Cancelar', kind: BtnKind.secondary, onTap: () => Navigator.pop(c)), Btn('Confirmar', onTap: _ok)),
/// ));
/// ```
class SheetBody extends StatelessWidget {
  const SheetBody({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
    this.footer,
    this.padding = 16,
    this.titleColor = C.ink,
    this.closable = true,
    this.trailing,
    this.top,
    this.fill = false,
    this.footerLine = false,
  });
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;
  final double padding;
  final Color titleColor;
  final bool closable;

  /// Widget à direita do título, no lugar do ✕ (ex.: um [QtyStepper]).
  final Widget? trailing;

  /// Faixa fixa entre o título e o conteúdo, que não rola (ex.: abas).
  final Widget? top;

  /// O conteúdo ocupa toda a altura disponível (folha de altura fixa: o
  /// rodapé não sobe quando o conteúdo é curto).
  final bool fill;

  /// Linha divisória acima do rodapé.
  final bool footerLine;

  @override
  Widget build(BuildContext context) {
    final showClose = title != null && trailing == null && closable && _SheetScope.dismissibleOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2)),
        ),
        if (title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(padding, 6, showClose ? padding - 7 : padding, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title!,
                          style: T.s(17, w: T.bold, c: titleColor, h: 1.25),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!, style: T.s(12.5, c: C.sub, h: 1.35)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (trailing != null) Padding(padding: const EdgeInsets.only(left: 10), child: trailing),
                if (showClose)
                  Semantics(
                    button: true,
                    label: 'Fechar',
                    child: InkResponse(
                      onTap: () => Navigator.maybePop(context),
                      radius: 22,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(color: C.bg, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 16, color: C.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (top != null) Padding(padding: EdgeInsets.fromLTRB(padding, 10, padding, 0), child: top),
        Flexible(
          fit: fill ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, title == null ? 14 : 10, padding, footer == null ? 20 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        if (footer != null)
          Container(
            decoration: footerLine ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
            padding: EdgeInsets.fromLTRB(padding, footerLine ? 10 : 8, padding, 16),
            child: SizedBox(width: double.infinity, child: footer),
          ),
      ],
    );
  }
}

/// Confirmação simples. Devolve `true` se confirmou.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Voltar',
  bool danger = false,
}) async =>
    await showSheet<bool>(
      context,
      (ctx) => SheetBody(
        title: title,
        children: [if (message != null) Text(message, style: T.body(c: C.sub))],
        footer: BtnRow(
          Btn(cancelLabel, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, false)),
          Btn(confirmLabel, kind: danger ? BtnKind.danger : BtnKind.navy, onTap: () => Navigator.pop(ctx, true)),
        ),
      ),
    ) ??
    false;

/// Aviso rápido (toast): faixa escura que aparece acima da barra inferior e
/// some em 2 s. Com `error: true` fica vermelha e dura 4 s (mensagem de falha
/// precisa de tempo para ser lida).
void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: T.s(13, c: C.white, w: T.semibold, h: 1.35),
        ),
        backgroundColor: error ? C.cancel : C.ink,
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        duration: Duration(seconds: error ? 4 : 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

// ── Blocos de tela ───────────────────────────────────────────────────────────

/// Cartão branco de raio 16 sobre o fundo `C.bg`. `padding` é o respiro
/// interno (use 0 com linhas [MenuRow], que já têm o próprio).
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.padding = 16, this.color = C.white});
  final Widget child;
  final double padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
    child: child,
  );
}

/// Destaque navy de raio 18 (total da mesa, valor restante, status do caixa).
/// Os textos de dentro devem ser brancos ou `C.navySub`.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = 16});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(18)),
    child: child,
  );
}

/// Rótulo de seção: 10,5 px, maiúsculas, com espaçamento de letras. `trailing`
/// fica alinhado à direita (ex.: um [Pill] com a contagem).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(2, 4, 2, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: T.section)),
        ?trailing,
      ],
    ),
  );
}

/// Etiqueta pequena de contagem/estado (raio 6): rosa por padrão.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.bg = C.magentaSoft, this.fg = C.magentaText});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(text, maxLines: 1, style: T.num(10.5, c: fg, h: 1.3)),
  );
}

/// Linha de lista com ícone navy, nome e algo à direita (contador, texto).
/// Coloque várias dentro de um `CardBox(padding: 0)`; `last: true` tira a
/// linha divisória da última.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.last = false,
    this.color = C.ink,
  });
  final IconData? icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 51),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: C.line)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 22, color: C.navy), const SizedBox(width: 12)],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  label,
                  style: T.s(14.5, w: T.semibold, c: color, h: 1.3),
                ),
              ),
            ),
            if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
          ],
        ),
      ),
    ),
  );
}

/// Contador magenta arredondado (número de notificações numa [MenuRow]).
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: C.magenta, borderRadius: BorderRadius.circular(9)),
    child: Text('$count', style: T.num(11, c: C.white, h: 1.3)),
  );
}

/// Chip de filtro com bolinha de cor e contagem ("● Livres 17"). O ativo fica
/// escuro. Use numa faixa com rolagem lateral.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, this.count, this.dot, this.onTap});
  final String label;
  final bool selected;
  final int? count;
  final Color? dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 44 px de área de toque em volta de um chip de ~30 px.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? C.ink : C.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? C.ink : C.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  count == null ? label : '$label $count',
                  style: T.num(12, w: T.semibold, c: selected ? C.white : C.ink, h: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Linha com interruptor (configurações).
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.sm(w: T.medium)),
              if (subtitle != null) Text(subtitle!, style: T.xs(c: C.zinc500)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: C.white,
          activeTrackColor: C.secondary500,
          inactiveThumbColor: C.white,
          inactiveTrackColor: C.zinc300,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ],
    ),
  );
}
