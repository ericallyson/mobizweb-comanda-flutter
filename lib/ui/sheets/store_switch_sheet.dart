import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../kit.dart';

/// "Trocar loja": a mesma troca que o nome da loja no topo do mapa já fazia
/// (`AuthStore.selectStore` → `POST /stores/{id}/select`), agora numa janela
/// por baixo usada pelo mapa de mesas e por Mais. Depois da troca os dados da
/// loja anterior são descartados e os da nova são carregados.
Future<void> showStoreSwitch(BuildContext context) async {
  if (!app.auth.hasMultipleStores) {
    toast(context, 'Seu usuário só tem acesso a esta loja.');
    return;
  }
  final picked = await showSheet<StoreRef>(context, (_) => const _StoreSwitchSheet());
  if (picked == null || !context.mounted) return;
  toast(context, 'Agora em ${picked.name}');
}

class _StoreSwitchSheet extends StatefulWidget {
  const _StoreSwitchSheet();

  @override
  State<_StoreSwitchSheet> createState() => _StoreSwitchSheetState();
}

class _StoreSwitchSheetState extends State<_StoreSwitchSheet> {
  String? _switchingId;
  String? _error;

  Future<void> _pick(StoreRef s) async {
    if (_switchingId != null) return;
    if (s.id == app.auth.store?.id) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _switchingId = s.id;
      _error = null;
    });
    final error = await app.auth.selectStore(s);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _switchingId = null;
        _error = 'Não foi possível trocar de loja. Tente novamente.';
      });
      return;
    }
    app.resetDomain();
    app.tables.fetch();
    app.menu.fetch();
    app.methods.load(force: true);
    app.notifications.fetch();
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final stores = app.auth.stores;
    final current = app.auth.store?.id;
    return SheetBody(
      title: 'Trocar loja',
      children: [
        ErrText(_error),
        CardBox(
          padding: 0,
          color: C.bg,
          child: Column(
            children: [
              for (final (i, s) in stores.indexed)
                MenuRow(
                  label: s.name,
                  last: i == stores.length - 1,
                  onTap: _switchingId != null ? null : () => _pick(s),
                  trailing: _switchingId == s.id
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: C.navy),
                        )
                      : (s.id == current ? const Icon(Icons.check, size: 18, color: C.navy) : null),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
