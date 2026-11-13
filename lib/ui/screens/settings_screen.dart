import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../print/receipt.dart';
import '../../stores/payments.dart';
import '../kit.dart';

/// Configurações do APARELHO: impressão, maquininha, pagamentos pendentes de
/// registro, "Fale conosco" (exigência da homologação Stone) e sobre.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.openPending = false});

  /// Veio do aviso de pagamentos pendentes (a seção já abre no topo).
  final bool openPending;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _busyId;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    app.settings.addListener(_changed);
    app.ledger.addListener(_changed);
  }

  @override
  void dispose() {
    app.settings.removeListener(_changed);
    app.ledger.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _testPrint() async {
    setState(() => _printing = true);
    final error = await app.terminal.printLines([
      const PText('Mobiz POS', align: PAlign.center, size: PSize.big, bold: true),
      PText(app.auth.store?.name ?? 'Teste de impressão', align: PAlign.center),
      const PDivider(),
      const PRow('1x Item de teste', 'R\$ 10,00'),
      const PRow('  + Adicional', 'R\$ 2,50', size: PSize.small),
      const PDivider(),
      const PRow('TOTAL', 'R\$ 12,50', size: PSize.big, bold: true),
      PText(dateTime(DateTime.now()), align: PAlign.center, size: PSize.small),
      const PText('Acentuação: ação, pão, três, último', size: PSize.small),
      const PGap(36),
    ]);
    if (!mounted) return;
    setState(() => _printing = false);
    toast(context, error ?? 'Impressão enviada.', error: error != null);
  }

  Future<void> _tef(PendingTef p, Future<String?> Function() action, String success) async {
    setState(() => _busyId = p.id);
    final error = await action();
    if (!mounted) return;
    setState(() => _busyId = null);
    toast(context, error ?? success, error: error != null);
  }

  Future<void> _dismiss(PendingTef p) async {
    final ok = await confirm(
      context,
      title: 'Descartar este registro?',
      message: p.isApproved
          ? 'A cobrança de ${brl(p.amount)} foi APROVADA na maquininha. Descartar não devolve o dinheiro ao cliente '
                'e não registra a venda. Use só depois de resolver pelo PDV web ou estornar.'
          : 'Confira antes no app da Stone se a cobrança de ${brl(p.amount)} foi aprovada.',
      confirmLabel: 'Descartar',
      danger: true,
    );
    if (ok) await app.ledger.dismiss(p);
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: T.label.copyWith(color: C.zinc400)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final t = app.terminal;
    final pending = app.ledger.pending;
    final host = Uri.tryParse(s.serverUrl)?.host ?? '';

    return Scaffold(
      backgroundColor: C.zinc50,
      body: Column(
        children: [
          AppHeader(title: 'Configurações', subtitle: 'Deste aparelho', onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (pending.isNotEmpty)
                  _section('Pagamentos pendentes (${pending.length})', [
                    Text(
                      'Cobranças da maquininha que ainda não estão registradas no Mobizweb. '
                      'Não cobre o cliente de novo: registre ou estorne.',
                      style: T.xs(c: C.zinc500),
                    ),
                    for (final p in pending) _pendingTile(p),
                  ]),
                _section('Impressão na maquininha', [
                  if (!t.canPrint)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Note('Impressora da Stone não encontrada neste aparelho.', center: false),
                    ),
                  SwitchRow(
                    title: 'Imprimir a conta',
                    subtitle: 'Ao pedir a conta da mesa ou da comanda',
                    value: s.printBill,
                    onChanged: s.setPrintBill,
                  ),
                  SwitchRow(
                    title: 'Imprimir os pedidos',
                    subtitle: 'Uma via a cada envio para a cozinha',
                    value: s.printOrders,
                    onChanged: s.setPrintOrders,
                  ),
                  SwitchRow(
                    title: 'Imprimir venda de balcão',
                    subtitle: 'Comprovante não fiscal da venda',
                    value: s.printCounter,
                    onChanged: s.setPrintCounter,
                  ),
                  SwitchRow(
                    title: 'Imprimir fechamento de caixa',
                    subtitle: 'Resumo com os valores contados',
                    value: s.printCashClose,
                    onChanged: s.setPrintCashClose,
                  ),
                  SwitchRow(
                    title: 'Imprimir como texto',
                    subtitle: 'Use se o terminal não imprimir imagem',
                    value: s.printAsText,
                    onChanged: s.setPrintAsText,
                  ),
                  const SizedBox(height: 6),
                  Btn(
                    'Imprimir página de teste',
                    kind: BtnKind.outline,
                    icon: Icons.print_outlined,
                    loading: _printing,
                    onTap: t.canPrint ? _testPrint : null,
                  ),
                ]),
                _section('Maquininha', [
                  Row(
                    children: [
                      Icon(
                        t.stoneAvailable ? Icons.check_circle : Icons.info_outline,
                        size: 18,
                        color: t.stoneAvailable ? C.emerald600 : C.amber600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.stoneAvailable
                              ? 'App de pagamento da Stone encontrado.'
                              : 'App de pagamento da Stone não encontrado: cartão e Pix são apenas registrados.',
                          style: T.xs(c: C.zinc600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchRow(
                    title: 'Cobrar cartão e Pix na maquininha',
                    subtitle: 'Abre o pagamento da Stone antes de registrar',
                    value: s.chargeOnTerminal,
                    onChanged: s.setChargeOnTerminal,
                  ),
                  if (!t.stoneAvailable)
                    SwitchRow(
                      title: 'Modo demonstração',
                      subtitle: 'Simula cobrança e impressão (só fora da maquininha)',
                      value: s.demoMode,
                      onChanged: s.setDemoMode,
                    ),
                ]),
                _section('Fale conosco', [
                  Text(Config.supportName, style: T.sm(w: T.semibold)),
                  if (Config.supportPhone.isNotEmpty) _contact(Icons.phone_outlined, Config.supportPhone),
                  if (Config.supportEmail.isNotEmpty) _contact(Icons.mail_outline, Config.supportEmail),
                  if (Config.supportSite.isNotEmpty) _contact(Icons.public, Config.supportSite),
                  const SizedBox(height: 4),
                  Text(
                    'Dúvidas sobre o pagamento na maquininha: use também o atendimento da Stone.',
                    style: T.xs(c: C.zinc400),
                  ),
                ]),
                _section('Sobre', [
                  KV('Aplicativo', 'Mobiz POS ${Config.appVersion}'),
                  if (host.isNotEmpty) KV('Loja', host),
                  if (app.auth.user != null) KV('Operador', app.auth.user!.name),
                  if (t.deviceLabel.isNotEmpty) KV('Aparelho', t.deviceLabel),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contact(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: C.zinc500),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(text, style: T.sm(c: C.zinc700))),
      ],
    ),
  );

  Widget _pendingTile(PendingTef p) {
    final busy = _busyId == p.id;
    final when = dateTime(DateTime.fromMillisecondsSinceEpoch(p.createdAt));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.isApproved ? C.red50 : C.amber50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.isApproved ? C.red200 : C.amber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.label, style: T.sm(w: T.bold))),
              Text(brl(p.amount), style: T.sm(w: T.bold, c: C.primary700)),
            ],
          ),
          Text(
            '${p.isApproved ? 'APROVADO na maquininha' : 'Desfecho não confirmado'} · $when'
            '${p.reference != null ? ' · ${p.reference}' : ''}',
            style: T.xs(c: C.zinc600),
          ),
          if (p.atk != null) Text('ATK ${p.atk}', style: T.s(11, c: C.zinc500)),
          if (p.lastError != null) Text(p.lastError!, style: T.xs(c: C.red700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (p.isApproved && p.kind != 'counter')
                SizedBox(
                  width: 140,
                  child: Btn(
                    'Registrar agora',
                    dense: true,
                    loading: busy,
                    onTap: busy ? null : () => _tef(p, () => app.ledger.retry(p), 'Pagamento registrado.'),
                  ),
                ),
              if (p.isApproved)
                SizedBox(
                  width: 110,
                  child: Btn(
                    'Estornar',
                    kind: BtnKind.outline,
                    dense: true,
                    onTap: busy ? null : () => _tef(p, () => app.ledger.refund(p), 'Estorno concluído.'),
                  ),
                ),
              if (p.atk != null)
                SizedBox(
                  width: 110,
                  child: Btn(
                    '2ª via',
                    kind: BtnKind.outline,
                    dense: true,
                    onTap: busy ? null : () => _tef(p, () => app.terminal.reprint(p.atk!), '2ª via enviada.'),
                  ),
                ),
              SizedBox(
                width: 110,
                child: Btn('Descartar', kind: BtnKind.dangerSoft, dense: true, onTap: busy ? null : () => _dismiss(p)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
