/// Formatação pt-BR sem `intl` (o pacote traria dados de todos os locales e
/// o APK precisa ficar enxuto).
library;

/// `1234.5` → `R$ 1.234,50`.
String brl(num? value) {
  final v = value ?? 0;
  final negative = v < 0;
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final frac = (cents % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write('.');
    buf.write(whole[i]);
  }
  return '${negative ? '-' : ''}R\$ $buf,$frac';
}

/// `12.5` → `12,50` (para pré-preencher campo de valor).
String decimalInput(num value) => value.toStringAsFixed(2).replaceAll('.', ',');

/// Aceita `12,5`, `12.5`, `1.234,56` e devolve número (0 se inválido).
double parseDecimal(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (s.isEmpty) return 0;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(s) ?? 0;
}

/// Reais → centavos inteiros (o deeplink da Stone trabalha em centavos).
int toCents(num value) => (value * 100).round();

/// Arredonda para 2 casas.
double round2(num n) => (n * 100).round() / 100;

/// Quantidade: inteira sem casas, fracionada com até 3 (`0,35`).
String qty(num q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// Percentual sem zeros à toa: `10` → `10`, `12.5` → `12,5`.
String percent(num p) {
  if (p == p.roundToDouble()) return p.toInt().toString();
  return p.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
}

String _two(int n) => n.toString().padLeft(2, '0');

DateTime? parseIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

/// `HH:MM` no fuso do aparelho.
String hhmm(String? iso) {
  final d = parseIso(iso);
  return d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}';
}

String hhmmss(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// `dd/MM/yyyy HH:MM`.
String dateTime(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String dateTimeIso(String? iso) {
  final d = parseIso(iso);
  return d == null ? '' : dateTime(d);
}

/// Remove acentos e caixa — busca tolerante (igual ao `normalize` do PWA).
String fold(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const to = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString().toLowerCase();
}

/// Comparação "natural" (Mesa 2 antes de Mesa 10), como `localeCompare(numeric)`.
int naturalCompare(String a, String b) {
  final ra = RegExp(r'(\d+|\D+)').allMatches(fold(a)).map((m) => m.group(0)!).toList();
  final rb = RegExp(r'(\d+|\D+)').allMatches(fold(b)).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final na = int.tryParse(ra[i]);
    final nb = int.tryParse(rb[i]);
    final c = (na != null && nb != null) ? na.compareTo(nb) : ra[i].compareTo(rb[i]);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}
