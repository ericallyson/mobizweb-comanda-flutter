import 'package:material_ui/material_ui.dart';

import 'kit.dart';

/// Cores de status de mesa — contraparte de `lib/tableStatusStyles.ts` do
/// PWA (e do PDV web). Fundo cheio com texto branco: livre = VERDE, ocupada =
/// VERMELHO, fechando = LARANJA, reservada = AZUL. O rótulo em texto é
/// obrigatório (verde × vermelho colapsa em deuteranopia).
class TableStatusStyle {
  const TableStatusStyle({
    required this.label,
    required this.bg,
    required this.border,
    required this.accent,
    this.text = C.white,
    this.dashed = false,
  });
  final String label;
  final Color bg;
  final Color border;
  final Color accent;
  final Color text;
  final bool dashed;

  Color get textMuted => text.withValues(alpha: 0.8);
}

const _neutral = TableStatusStyle(label: '—', bg: C.zinc400, border: C.zinc500, accent: C.zinc600);

const tableStatusStyles = <String, TableStatusStyle>{
  'available': TableStatusStyle(label: 'Livre', bg: C.emerald500, border: C.emerald600, accent: C.emerald700),
  'occupied': TableStatusStyle(label: 'Ocupada', bg: C.red500, border: C.red600, accent: C.red700),
  'closing': TableStatusStyle(label: 'Fechando', bg: C.orange500, border: C.orange600, accent: C.orange700),
  'reserved': TableStatusStyle(label: 'Reservada', bg: C.blue500, border: C.blue600, accent: C.blue700),
};

/// Mesa OCIOSA — estado visual calculado no app (`stores/tables.dart`), não
/// vem do backend. Âmbar com texto escuro.
const tableIdleStyle = TableStatusStyle(
  label: 'Ociosa',
  bg: C.amber400,
  border: C.amber700,
  accent: C.amber700,
  text: C.zinc900,
  dashed: true,
);

TableStatusStyle tableStatusStyle(String? status) => tableStatusStyles[status] ?? _neutral;
