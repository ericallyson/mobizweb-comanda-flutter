import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/storage.dart';

/// Preferências do APARELHO (não do usuário): endereço da loja, grade de
/// mesas, impressão e cobrança na maquininha. Sobrevivem ao logout.
class Settings extends ChangeNotifier {
  Settings(this._store) {
    _serverInput = _store.getString('server_input') ?? Config.presetStore;
    _gridCols = _store.getInt('grid_cols', 2).clamp(2, 4);
    _sortMode = _store.getString('sort_mode') ?? 'number';
    _printBill = _store.getBool('print_bill', true);
    _printOrders = _store.getBool('print_orders', false);
    _printCounter = _store.getBool('print_counter', true);
    _printCashClose = _store.getBool('print_cash_close', false);
    _printAsText = _store.getBool('print_as_text', false);
    _chargeOnTerminal = _store.getBool('charge_on_terminal', true);
    _demoMode = _store.getBool('demo_mode', false);
    _forceStone = _store.getBool('force_stone', false);
  }

  final LocalStore _store;

  late String _serverInput;
  late int _gridCols;
  late String _sortMode;
  late bool _printBill;
  late bool _printOrders;
  late bool _printCounter;
  late bool _printCashClose;
  late bool _printAsText;
  late bool _chargeOnTerminal;
  late bool _demoMode;
  late bool _forceStone;

  /// O que o operador digitou ("minhaloja" ou o domínio completo).
  String get serverInput => _serverInput;

  /// Origem do tenant, ex.: `https://minhaloja.mobizweb.com.br`.
  String get serverUrl => normalizeServerUrl(_serverInput, defaultDomain: Config.defaultDomain);

  int get gridCols => _gridCols;

  /// `number` | `title` | `status`.
  String get sortMode => _sortMode;

  /// Imprime a conta na maquininha ao pedir a conta / pela conta parcial.
  bool get printBill => _printBill;

  /// Imprime uma via do pedido ao enviar para a cozinha.
  bool get printOrders => _printOrders;

  /// Imprime o comprovante da venda de balcão.
  bool get printCounter => _printCounter;

  /// Imprime o resumo ao fechar o caixa.
  bool get printCashClose => _printCashClose;

  /// Texto puro em vez de imagem (fallback para terminal que recusa imagem).
  bool get printAsText => _printAsText;

  /// Cartão/Pix cobrados pelo app de pagamento da Stone (deeplink).
  bool get chargeOnTerminal => _chargeOnTerminal;

  /// Simula maquininha e impressora em aparelho SEM os apps da Stone.
  bool get demoMode => _demoMode;

  /// Usa os apps da Stone mesmo que a detecção automática não os encontre
  /// (o Android pode esconder de um app a existência de outro).
  bool get forceStone => _forceStone;

  void setServerInput(String v) => _set(() => _serverInput = v.trim(), () => _store.setString('server_input', v.trim()));
  void setGridCols(int v) => _set(() => _gridCols = v, () => _store.setInt('grid_cols', v));
  void setSortMode(String v) => _set(() => _sortMode = v, () => _store.setString('sort_mode', v));
  void setPrintBill(bool v) => _set(() => _printBill = v, () => _store.setBool('print_bill', v));
  void setPrintOrders(bool v) => _set(() => _printOrders = v, () => _store.setBool('print_orders', v));
  void setPrintCounter(bool v) => _set(() => _printCounter = v, () => _store.setBool('print_counter', v));
  void setPrintCashClose(bool v) => _set(() => _printCashClose = v, () => _store.setBool('print_cash_close', v));
  void setPrintAsText(bool v) => _set(() => _printAsText = v, () => _store.setBool('print_as_text', v));
  void setChargeOnTerminal(bool v) => _set(() => _chargeOnTerminal = v, () => _store.setBool('charge_on_terminal', v));
  void setDemoMode(bool v) => _set(() => _demoMode = v, () => _store.setBool('demo_mode', v));
  void setForceStone(bool v) => _set(() => _forceStone = v, () => _store.setBool('force_stone', v));

  void _set(VoidCallback apply, Future<void> Function() persist) {
    apply();
    notifyListeners();
    persist();
  }
}
