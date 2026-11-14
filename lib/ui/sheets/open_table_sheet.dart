import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../kit.dart';

typedef OpenTableData = ({int? guestCount, String? customerName, List<String> comandas});

/// "Abrir mesa": pessoas, cliente e (se a loja usa) as comandas iniciais.
class OpenTableSheet extends StatefulWidget {
  const OpenTableSheet({super.key, required this.table, required this.enableComandas});
  final DiningTable table;
  final bool enableComandas;

  @override
  State<OpenTableSheet> createState() => _OpenTableSheetState();
}

class _OpenTableSheetState extends State<OpenTableSheet> {
  final _guests = TextEditingController();
  final _customer = TextEditingController();
  final _comanda = TextEditingController();
  final _labels = <String>[];
  bool _withComandas = false;

  @override
  void dispose() {
    _guests.dispose();
    _customer.dispose();
    _comanda.dispose();
    super.dispose();
  }

  void _addComanda() {
    final label = _comanda.text.trim();
    if (label.isEmpty) return;
    setState(() {
      if (!_labels.any((l) => l.toLowerCase() == label.toLowerCase())) _labels.add(label);
      _comanda.clear();
    });
  }

  void _confirm() {
    _addComanda();
    final guests = int.tryParse(_guests.text.trim());
    final name = _customer.text.trim();
    Navigator.pop<OpenTableData>(context, (
      guestCount: (guests != null && guests >= 1 && guests <= 100) ? guests : null,
      customerName: name.isEmpty ? null : name,
      comandas: widget.enableComandas && _withComandas ? List.of(_labels) : const <String>[],
    ));
  }

  @override
  Widget build(BuildContext context) => SheetBody(
    padding: 24,
    children: [
      Text('Abrir ${widget.table.title}', style: T.lg(w: T.bold, c: C.primary700)),
      const SizedBox(height: 2),
      Text('Informe o número de pessoas e o cliente (opcionais).', style: T.sm(c: C.zinc500)),
      const SizedBox(height: 18),
      Field(
        label: 'Pessoas',
        controller: _guests,
        hint: 'Ex: 2',
        keyboard: TextInputType.number,
        formatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 3,
        action: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      Field(
        label: 'Nome do cliente',
        controller: _customer,
        hint: 'Opcional. Aparece na mesa e nas impressões',
        maxLength: 120,
      ),
      if (widget.enableComandas) ...[
        const SizedBox(height: 14),
        Text('COMANDAS', style: T.label),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Choice('Somente mesa', selected: !_withComandas, onTap: () => setState(() => _withComandas = false))),
            const SizedBox(width: 8),
            Expanded(child: Choice('Com comandas', selected: _withComandas, onTap: () => setState(() => _withComandas = true))),
          ],
        ),
        if (_withComandas) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Field(
                  controller: _comanda,
                  hint: 'Nº ou nome (ex.: 2 ou Maria)',
                  maxLength: 60,
                  onSubmitted: (_) => _addComanda(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _comanda.text.trim().isEmpty ? 0.4 : 1,
                child: Tap(
                  onTap: _comanda.text.trim().isEmpty ? null : _addComanda,
                  color: C.white,
                  border: const BorderSide(color: C.primary300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Text('+', style: T.base(w: T.semibold, c: C.primary600)),
                ),
              ),
            ],
          ),
          if (_labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _labels.length; i++)
                    Tap(
                      onTap: () => setState(() => _labels.removeAt(i)),
                      color: C.primary50,
                      radius: 999,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_labels[i], style: T.xs(w: T.semibold, c: C.primary700)),
                          const SizedBox(width: 4),
                          const Icon(Icons.close, size: 12, color: C.primary400),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text('Você também pode abrir mais comandas depois, em "Comandas da mesa".', style: T.s(11, c: C.zinc400)),
        ],
      ],
    ],
    footer: BtnRow(
      Btn('Cancelar', kind: BtnKind.outline, onTap: () => Navigator.pop(context)),
      Btn('Abrir mesa', kind: BtnKind.accent, onTap: _confirm),
    ),
  );
}
