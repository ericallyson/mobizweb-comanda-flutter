import 'package:http/http.dart' as http;

import 'core/api.dart';
import 'core/native.dart';
import 'core/storage.dart';
import 'stone/terminal.dart';
import 'stores/auth.dart';
import 'stores/cash.dart';
import 'stores/counter.dart';
import 'stores/menu.dart';
import 'stores/payments.dart';
import 'stores/session.dart';
import 'stores/settings.dart';
import 'stores/tables.dart';

/// Raiz de dependências do app: um objeto de cada store/serviço, criado na
/// abertura. As telas leem por [app] e escutam os `ChangeNotifier`s.
class App {
  App._({
    required this.native,
    required this.store,
    required this.api,
    required this.settings,
    required this.terminal,
    required this.auth,
    required this.tables,
    required this.menu,
    required this.session,
    required this.cash,
    required this.counter,
    required this.methods,
    required this.ledger,
  });

  final Native native;
  final LocalStore store;
  final Api api;
  final Settings settings;
  final Terminal terminal;
  final AuthStore auth;
  final TablesStore tables;
  final MenuStore menu;
  final SessionStore session;
  final CashStore cash;
  final CounterStore counter;
  final PaymentMethodsStore methods;
  final TefLedger ledger;

  static App? _instance;
  static App get instance => _instance!;

  /// `backend`/`client` só são passados nos testes.
  static Future<App> boot({KeyValueBackend? backend, http.Client? client, bool probeDevice = true}) async {
    const native = Native();
    String? filesDir;
    if (backend == null) {
      final info = await native.deviceInfo();
      filesDir = info['filesDir'] as String?;
    }
    final store = await LocalStore.open(backend ?? native, filesDir: filesDir);
    final api = Api(client: client);
    final settings = Settings(store);
    api.baseUrl = settings.serverUrl;
    final terminal = Terminal(native, settings);
    final auth = AuthStore(api, store);
    final a = App._(
      native: native,
      store: store,
      api: api,
      settings: settings,
      terminal: terminal,
      auth: auth,
      tables: TablesStore(api, store),
      menu: MenuStore(api, store),
      session: SessionStore(api),
      cash: CashStore(api),
      counter: CounterStore(api),
      methods: PaymentMethodsStore(api),
      ledger: TefLedger(api, store, terminal, native),
    );
    // 401 = token revogado: derruba a sessão local e a raiz volta ao login.
    api.onUnauthorized = auth.clearLocal;
    await auth.restore();
    if (probeDevice) {
      await terminal.init();
      await a.ledger.init();
    }
    _instance = a;
    return a;
  }

  /// Limpa o que é do operador/loja (logout ou troca de loja) — num aparelho
  /// compartilhado o próximo usuário não pode ver os dados do anterior.
  void resetDomain() {
    tables.reset();
    menu.reset();
    session.clear();
    cash.reset();
    counter.reset();
    methods.reset();
  }

  /// Nome enviado em `device_name` no login. Sem número de série: lê-lo exige
  /// READ_PHONE_STATE, permissão proibida pela Stone.
  String get deviceName {
    final label = terminal.deviceLabel.trim();
    return label.isEmpty ? 'mobiz-pos' : 'mobiz-pos $label';
  }
}

App get app => App.instance;
