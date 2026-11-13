import 'package:material_ui/material_ui.dart';

/// Paleta do Mobiz — a mesma do PWA do garçom (`apps/garcom-pwa/src/style.css`
/// + escala zinc/emerald/red/orange/blue/amber do Tailwind). Se mudar lá, mude
/// aqui: o app precisa parecer a comanda.
abstract final class C {
  // Primary — navy
  static const primary50 = Color(0xFFF0F0F9);
  static const primary100 = Color(0xFFD4D5E8);
  static const primary200 = Color(0xFFA9AAD1);
  static const primary300 = Color(0xFF7E80BA);
  static const primary400 = Color(0xFF5355A3);
  static const primary500 = Color(0xFF282A8C);
  static const primary600 = Color(0xFF080A52);
  static const primary700 = Color(0xFF060842);
  static const primary800 = Color(0xFF050633);
  static const primary900 = Color(0xFF030524);

  // Secondary — magenta
  static const secondary50 = Color(0xFFFDEBF3);
  static const secondary100 = Color(0xFFFAC6DC);
  static const secondary200 = Color(0xFFF593B9);
  static const secondary500 = Color(0xFFED2188);
  static const secondary600 = Color(0xFFC91973);
  static const secondary700 = Color(0xFFA0145C);

  // Zinc
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);

  static const white = Color(0xFFFFFFFF);

  // Status
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);

  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red300 = Color(0xFFFCA5A5);
  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const red800 = Color(0xFF991B1B);

  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const orange700 = Color(0xFFC2410C);

  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);

  static const sky100 = Color(0xFFE0F2FE);
  static const sky700 = Color(0xFF0369A1);
  static const green100 = Color(0xFFDCFCE7);
  static const green700 = Color(0xFF15803D);
}

/// Escala tipográfica do Tailwind usada no PWA (text-xs … text-3xl).
abstract final class T {
  static TextStyle s(double size, {FontWeight w = FontWeight.w400, Color c = C.zinc800, double? h}) =>
      TextStyle(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: 0);

  static TextStyle xs({FontWeight w = FontWeight.w400, Color c = C.zinc800}) => s(12, w: w, c: c, h: 1.33);
  static TextStyle sm({FontWeight w = FontWeight.w400, Color c = C.zinc800}) => s(14, w: w, c: c, h: 1.43);
  static TextStyle base({FontWeight w = FontWeight.w400, Color c = C.zinc800}) => s(16, w: w, c: c, h: 1.4);
  static TextStyle lg({FontWeight w = FontWeight.w400, Color c = C.zinc800}) => s(18, w: w, c: c, h: 1.35);
  static TextStyle xl({FontWeight w = FontWeight.w400, Color c = C.zinc800}) => s(20, w: w, c: c, h: 1.3);

  /// Rótulo de campo: `text-xs font-semibold tracking-wide uppercase text-zinc-500`.
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: C.zinc500,
    letterSpacing: 0.3,
    height: 1.33,
  );

  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const black = FontWeight.w900;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.primary600,
    primary: C.primary600,
    secondary: C.secondary500,
    surface: C.white,
    error: C.red500,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.zinc50,
    splashFactory: InkRipple.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.primary500,
      selectionColor: C.primary100,
      selectionHandleColor: C.primary500,
    ),
    // Sem animação de página pesada: maquininha tem CPU modesta.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeUpwardsPageTransitionsBuilder()},
    ),
  );
}
