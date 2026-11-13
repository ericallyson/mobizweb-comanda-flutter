/// Leitura tolerante de JSON: a API manda dinheiro ora como número, ora como
/// string decimal (`numeric(15,4)`), e campos novos podem faltar em servidor
/// antigo. Nenhum parser pode derrubar a tela por causa disso.
library;

typedef Json = Map<String, dynamic>;

Json asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Json> asList(dynamic v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
  return fallback;
}

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return fallback;
}

String asString(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}
