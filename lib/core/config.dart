/// Configuração de build. Nada de URL, telefone ou segredo espalhado pelo
/// código: tudo entra por `--dart-define` (ver `tool/build.*` e o README).
abstract final class Config {
  /// Domínio central do Mobizweb. O operador digita só o endereço da loja
  /// ("minhaloja") e o app completa com este domínio.
  static const defaultDomain = String.fromEnvironment('MOBIZ_DOMAIN', defaultValue: 'mobizweb.com.br');

  /// Loja pré-configurada (opcional) — útil para gerar um APK já apontado.
  static const presetStore = String.fromEnvironment('MOBIZ_STORE');

  /// "Fale Conosco" — exigência da homologação Stone (precisa estar visível).
  static const supportName = String.fromEnvironment('MOBIZ_SUPPORT_NAME', defaultValue: 'Suporte Mobiz');
  static const supportPhone = String.fromEnvironment('MOBIZ_SUPPORT_PHONE');
  static const supportEmail = String.fromEnvironment('MOBIZ_SUPPORT_EMAIL');
  static const supportSite = String.fromEnvironment('MOBIZ_SUPPORT_SITE', defaultValue: 'www.mobizweb.com.br');

  /// Versão exibida em Configurações (o build injeta a do pubspec).
  static const appVersion = String.fromEnvironment('MOBIZ_APP_VERSION', defaultValue: 'dev');

  /// `tef_provider` gravado no pagamento (contrato `docs/api-comanda.md` §7).
  static const tefProvider = 'stone_deeplink';

  /// Scheme de retorno dos deeplinks da Stone — o MESMO do AndroidManifest.
  static const returnScheme = 'mobizpos';

  /// Largura útil da bobina de 58 mm, em pontos.
  static const paperWidthPx = 384;
}
