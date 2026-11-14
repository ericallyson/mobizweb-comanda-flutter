import 'package:material_ui/material_ui.dart';

import '../stores/tables.dart';
import 'kit.dart';

/// Cores de status de mesa, contraparte de `lib/tableStatusStyles.ts` do PWA
/// (e do PDV web). NÃO mudaram no layout novo. Fundo cheio com texto branco:
/// livre = VERDE, ocupada = VERMELHO, fechando = LARANJA, reservada = AZUL;
/// ociosa = ÂMBAR com texto escuro. No card o status se lê pela cor; o nome
/// por extenso fica nos chips de filtro e no rótulo de acessibilidade
/// (verde × vermelho colapsa em deuteranopia).
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

const _neutral = TableStatusStyle(label: 'Sem status', bg: C.zinc400, border: C.zinc500, accent: C.zinc600);

const tableStatusStyles = <String, TableStatusStyle>{
  'available': TableStatusStyle(label: 'Livre', bg: C.emerald500, border: C.emerald600, accent: C.emerald700),
  'occupied': TableStatusStyle(label: 'Ocupada', bg: C.red500, border: C.red600, accent: C.red700),
  'closing': TableStatusStyle(label: 'Fechando', bg: C.orange500, border: C.orange600, accent: C.orange700),
  'reserved': TableStatusStyle(label: 'Reservada', bg: C.blue500, border: C.blue600, accent: C.blue700),
};

/// Mesa OCIOSA: estado visual calculado no app (`stores/tables.dart`), não
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

/// Estilo de um grupo do mapa (chip de filtro e card): [TableFilter.idle] usa
/// o âmbar de ociosa; os demais, a cor do status.
TableStatusStyle tableGroupStyle(TableFilter group) => switch (group) {
  TableFilter.idle => tableIdleStyle,
  TableFilter.available => tableStatusStyle('available'),
  TableFilter.occupied => tableStatusStyle('occupied'),
  TableFilter.closing => tableStatusStyle('closing'),
  TableFilter.reserved => tableStatusStyle('reserved'),
  _ => _neutral,
};
