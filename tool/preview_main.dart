// Prévia do app FORA do Android (navegador/desktop), para desenvolver e
// revisar telas sem maquininha. Usa armazenamento em memória, modo
// demonstração e o servidor falso de `tool/mock-server.mjs`.
//
//   node tool/mock-server.mjs
//   flutter run -d chrome -t tool/preview_main.dart   (precisa da plataforma web)
import 'package:material_ui/material_ui.dart';
import 'package:mobizweb_pos/app.dart';
import 'package:mobizweb_pos/core/storage.dart';
import 'package:mobizweb_pos/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const server = String.fromEnvironment('PREVIEW_SERVER', defaultValue: 'http://localhost:8787');
  final backend = MemoryBackend()
    ..values['server_input'] = server
    ..values['demo_mode'] = '1'
    ..values['print_orders'] = '1';
  await App.boot(backend: backend, probeDevice: false);
  app.terminal.onPreview = previewPrint;
  runApp(const MobizApp());
}
