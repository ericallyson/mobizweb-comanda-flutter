import 'dart:math';

final _rng = Random.secure();

/// UUID v7 (timestamp em ms + aleatório) — mesmo formato que o PWA usa nas
/// `Idempotency-Key` e que o backend usa nas PKs (ADR-004).
String uuidV7() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[0] = (ms >> 40) & 0xff;
  b[1] = (ms >> 32) & 0xff;
  b[2] = (ms >> 24) & 0xff;
  b[3] = (ms >> 16) & 0xff;
  b[4] = (ms >> 8) & 0xff;
  b[5] = ms & 0xff;
  b[6] = (b[6] & 0x0f) | 0x70; // versão 7
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
