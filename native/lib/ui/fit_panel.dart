import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/fit.dart';
import '../domain/product.dart';
import 'feedback.dart';
import 'paper.dart';

/// Size suggestion from the owner's own history, the store's size chart, and
/// the "I bought this" fit log for one imported item. Everything here stays on
/// the device.
class FitPanel extends StatefulWidget {
  const FitPanel({super.key, required this.product, required this.repository});
  final Product product;
  final CatalogRepository repository;
  @override
  State<FitPanel> createState() => _FitPanelState();
}

class _FitPanelState extends State<FitPanel> {
  late FitRecord? _saved = widget.repository.fitFor(widget.product.id);
  late final _size = TextEditingController(text: _saved?.size ?? '');
  late final _note = TextEditingController(text: _saved?.note ?? '');
  late bool _kept = _saved?.kept ?? true;
  late String _fit = _saved?.fit ?? 'right';
  bool _editing = false;

  @override
  void dispose() {
    _size.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final size = _size.text.trim();
    if (size.isEmpty) return;
    final p = widget.product;
    final record = FitRecord(
      productId: p.id,
      brand: p.brand,
      size: size,
      kept: _kept,
      fit: _fit,
      note: _note.text.trim(),
      item: p.name,
    );
    widget.repository.setFit(record);
    FeedbackScope.of(context).play(Cue.success);
    setState(() {
      _saved = record;
      _editing = false;
    });
  }

  void _clear() {
    widget.repository.clearFit(widget.product.id);
    FeedbackScope.of(context).play(Cue.toggle);
    setState(() {
      _saved = null;
      _editing = false;
      _size.clear();
      _note.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final suggestion = suggestSize(p.brand, widget.repository.fits(), excludeProduct: p.id);
    final saved = _saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Size and fit'),
        const SizedBox(height: Space.m),
        if (suggestion != null)
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your size at ${p.brand}: ${suggestion.size}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.xs),
                Text(suggestion.reason, style: const TextStyle(fontSize: 12.5)),
                for (final line in suggestion.evidence.take(5))
                  Text('• $line', style: const TextStyle(color: Tone.inkSoft, fontSize: 12)),
              ],
            ),
          )
        else
          Text(
            p.brand.isEmpty
                ? 'Record what you bought to build your own size profile.'
                : 'No ${p.brand} sizes recorded yet. Record what you buy and keep, and Vastra will remember your size for this brand.',
            style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5),
          ),
        if (p.sizeChart.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text("The store's size chart", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: Space.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: Tone.line),
              children: [
                for (final (i, row) in p.sizeChart.indexed)
                  TableRow(
                    children: [
                      for (var c = 0; c < p.sizeChart.first.length; c++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                          child: Text(
                            c < row.length ? row[c] : '',
                            style: TextStyle(fontSize: 12, fontWeight: i == 0 ? FontWeight.w600 : null),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.m),
        if (saved != null && !_editing) ...[
          Text('You bought: ${saved.summary.substring(saved.summary.indexOf(':') + 2)}.'),
          if (saved.note.isNotEmpty)
            Text('Fits me: ${saved.note}', style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5)),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            children: [
              PaperButton(
                label: 'Edit',
                icon: Icons.edit_outlined,
                compact: true,
                onPressed: () => setState(() => _editing = true),
              ),
              PaperButton(label: 'Forget', icon: Icons.close, compact: true, onPressed: _clear),
            ],
          ),
        ] else if (!_editing)
          Align(
            alignment: Alignment.centerLeft,
            child: PaperButton(
              label: 'I bought this',
              icon: Icons.straighten,
              compact: true,
              onPressed: () => setState(() => _editing = true),
            ),
          )
        else ...[
          if (p.sizes.isNotEmpty)
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final s in p.sizes.take(20))
                  ChoiceChip(
                    label: Text(s),
                    selected: _size.text == s,
                    onSelected: (_) => setState(() => _size.text = s),
                  ),
              ],
            ),
          const SizedBox(height: Space.s),
          PaperField(
            controller: _size,
            label: 'Size you bought',
            maxLength: 30,
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final (value, label) in [(true, 'Kept it'), (false, 'Returned it')])
                ChoiceChip(
                  label: Text(label),
                  selected: _kept == value,
                  onSelected: (_) => setState(() => _kept = value),
                ),
            ],
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final (value, label) in [
                ('small', 'Ran small'),
                ('right', 'Fit right'),
                ('large', 'Ran large'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _fit == value,
                  onSelected: (_) => setState(() => _fit = value),
                ),
            ],
          ),
          const SizedBox(height: Space.s),
          PaperField(
            controller: _note,
            label: 'Fits me note (optional)',
            hint: 'Long in the sleeve, roomy at the hip',
            maxLength: 200,
          ),
          Wrap(
            spacing: Space.s,
            children: [
              CopperButton(
                label: 'Save fit',
                icon: Icons.check,
                onPressed: _size.text.trim().isEmpty ? null : _save,
              ),
              PaperButton(label: 'Cancel', compact: true, onPressed: () => setState(() => _editing = false)),
            ],
          ),
        ],
        const SizedBox(height: Space.xs),
        const Text(
          'Sizes and fit notes stay on this device. Exports leave them out.',
          style: TextStyle(color: Tone.inkSoft, fontSize: 11.5),
        ),
      ],
    );
  }
}
