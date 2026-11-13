/// Kit visual do app — os mesmos blocos do PWA do garçom (cabeçalho navy,
/// botões `rounded-xl`, campos com borda zinc, folhas que sobem de baixo).
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

enum BtnKind { primary, accent, outline, danger, dangerSoft, success, warn }

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
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool loading;

  /// `py-2.5 text-xs` em vez de `py-3 text-sm`.
  final bool dense;
  final IconData? icon;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (C.primary600, C.white, null),
      BtnKind.accent => (C.secondary500, C.white, null),
      BtnKind.outline => (C.white, C.zinc600, const BorderSide(color: C.zinc200)),
      BtnKind.danger => (C.red500, C.white, null),
      BtnKind.dangerSoft => (C.red50, C.red600, null),
      BtnKind.success => (C.emerald600, C.white, null),
      BtnKind.warn => (C.amber600, C.white, null),
    };
    final enabled = onTap != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Tap(
        onTap: enabled ? onTap : null,
        color: bg,
        border: border,
        radius: 12,
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 12, vertical: dense ? 10 : 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
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
                style: T.s(dense ? 12 : 14, w: bold ? T.bold : T.semibold, c: fg, h: 1.3),
              ),
            ),
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

/// Botão quadrado do cabeçalho (`bg-primary-700 rounded-lg p-2`).
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, this.onTap, this.badge, this.tooltip, this.spinning = false});
  final IconData icon;
  final VoidCallback? onTap;
  final int? badge;
  final String? tooltip;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    Widget child = Tap(
      onTap: onTap,
      color: C.primary700,
      radius: 8,
      splash: Colors.white24,
      padding: const EdgeInsets.all(9),
      child: spinning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.primary100),
            )
          : Icon(icon, size: 18, color: C.primary100),
    );
    if (badge != null && badge! > 0) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: C.amber500, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text('$badge', style: T.s(10, w: T.bold, c: C.white, h: 1.2)),
            ),
          ),
        ],
      );
    }
    return Semantics(button: true, label: tooltip, child: child);
  }
}

// ── Cabeçalho ────────────────────────────────────────────────────────────────

/// Barra navy do topo, respeitando a área segura.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.subtitle, this.onBack, this.actions = const [], this.subtitleWidget});
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(statusBarColor: C.primary600),
    child: Container(
      color: C.primary600,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (onBack != null) ...[
              HeaderButton(icon: Icons.arrow_back, onTap: onBack, tooltip: 'Voltar'),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(16, w: T.bold, c: C.white, h: 1.25),
                  ),
                  if (subtitleWidget != null)
                    subtitleWidget!
                  else if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.xs(c: C.primary200),
                    ),
                ],
              ),
            ),
            for (final a in actions) Padding(padding: const EdgeInsets.only(left: 6), child: a),
          ],
        ),
      ),
    ),
  );
}

// ── Campos ───────────────────────────────────────────────────────────────────

InputDecoration fieldDecoration({String? hint, Color fill = C.white, Color focus = C.primary500, Widget? suffix}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: T.sm(c: C.zinc400),
    isDense: true,
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: b(C.zinc200),
    enabledBorder: b(C.zinc200),
    disabledBorder: b(C.zinc200),
    focusedBorder: b(focus, 1.5),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
  );
}

/// Rótulo em caixa alta + campo (`space-y-1` do PWA).
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
    this.focus = C.primary500,
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
      if (label != null) ...[Text(label!.toUpperCase(), style: T.label), const SizedBox(height: 4)],
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
        style: large ? T.base(c: enabled ? C.zinc800 : C.zinc400) : T.sm(c: enabled ? C.zinc800 : C.zinc400),
        decoration: fieldDecoration(hint: hint, focus: focus, fill: enabled ? fill : C.zinc50),
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
    this.focus = C.primary500,
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

/// Contador `− 1 +` (botões redondos com borda).
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.value, this.onMinus, this.onPlus, this.size = 32});
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final double size;

  Widget _b(IconData icon, VoidCallback? onTap) => Opacity(
    opacity: onTap == null ? 0.4 : 1,
    child: Tap(
      onTap: onTap,
      color: C.white,
      radius: size,
      border: const BorderSide(color: C.zinc200),
      child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: C.zinc700)),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _b(Icons.remove, onMinus),
      SizedBox(
        width: size * 0.9,
        child: Text(value, textAlign: TextAlign.center, style: T.sm(w: T.semibold)),
      ),
      _b(Icons.add, onPlus),
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

/// Folha que sobe de baixo (`rounded-t-2xl`, alça cinza, largura máx. 448),
/// rolável e que sobe junto com o teclado.
Future<R?> showSheet<R>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) =>
    showModalBottomSheet<R>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 448,
              maxHeight: (MediaQuery.sizeOf(ctx).height - MediaQuery.viewInsetsOf(ctx).bottom) * 0.92,
            ),
            child: Material(
              color: C.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(top: false, child: builder(ctx)),
            ),
          ),
        ),
      ),
    );

/// Corpo padrão de folha: alça, título, conteúdo rolável e rodapé fixo.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, this.title, this.subtitle, required this.children, this.footer, this.padding = 16, this.titleColor = C.zinc800});
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;
  final double padding;
  final Color titleColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 10),
      Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(color: C.zinc200, borderRadius: BorderRadius.circular(2)),
      ),
      if (title != null)
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 10, padding, 0),
          child: Text(title!, textAlign: TextAlign.center, style: T.base(w: T.bold, c: titleColor)),
        ),
      if (subtitle != null)
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 2, padding, 0),
          child: Text(subtitle!, textAlign: TextAlign.center, style: T.sm(c: C.zinc500)),
        ),
      Flexible(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 14, padding, footer == null ? 20 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
      if (footer != null)
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 8, padding, 16),
          child: SizedBox(width: double.infinity, child: footer),
        ),
    ],
  );
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
        children: [if (message != null) Text(message, textAlign: TextAlign.center, style: T.sm(c: C.zinc600))],
        footer: BtnRow(
          Btn(cancelLabel, kind: BtnKind.outline, onTap: () => Navigator.pop(ctx, false)),
          Btn(confirmLabel, kind: danger ? BtnKind.danger : BtnKind.primary, onTap: () => Navigator.pop(ctx, true)),
        ),
      ),
    ) ??
    false;

/// Aviso rápido no rodapé.
void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: T.sm(c: C.white, w: T.medium)),
        backgroundColor: error ? C.red700 : C.zinc800,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error ? 5 : 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Cartão branco (`rounded-xl bg-white p-5 shadow-sm`).
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.padding = 18});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: C.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: child,
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

/// Valor em destaque (`text-primary-700 text-lg font-bold`).
Text bigMoney(num value, {double size = 18}) =>
    Text(brl(value), textAlign: TextAlign.center, style: T.s(size, w: T.bold, c: C.primary700, h: 1.3));
