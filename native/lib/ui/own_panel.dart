import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/product.dart';
import '../domain/wardrobe.dart';
import 'feedback.dart';
import 'paper.dart';

/// Marks one imported item as owned, records what was paid, and logs the days
/// it was worn, so cost per wear can be worked out. Stays on the device.
class OwnPanel extends StatefulWidget {
  const OwnPanel({super.key, required this.product, required this.repository, this.today});
  final Product product;
  final CatalogRepository repository;

  /// Fixed day for tests.
  final DateTime? today;
  @override
  State<OwnPanel> createState() => _OwnPanelState();
}

class _OwnPanelState extends State<OwnPanel> {
  late Own? _own = widget.repository.owned()[widget.product.id];
  late final _price = TextEditingController(text: _initialPrice());
  late final _currency = TextEditingController(text: _own?.currency ?? _offer?.currency ?? '');

  Offer? get _offer => widget.product.offers.where((o) => o.price != null).firstOrNull;

  String _initialPrice() {
    final v = _own?.price ?? _offer?.price;
    return v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _price.dispose();
    _currency.dispose();
    super.dispose();
  }

  DateTime get _now => widget.today ?? DateTime.now();

  void _save({DateTime? boughtOn}) {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    final own = Own(
      productId: widget.product.id,
      price: price != null && price >= 0 ? price : null,
      currency: _currency.text.trim().toUpperCase(),
      boughtOn: boughtOn ?? _own?.boughtOn,
    );
    widget.repository.setOwn(own);
    setState(() => _own = own);
  }

  void _toggle(bool on) {
    FeedbackScope.of(context).play(Cue.toggle);
    if (on) {
      _save();
    } else {
      widget.repository.unown(widget.product.id);
      setState(() => _own = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = _own;
    final days = widget.repository.wearDays(widget.product.id);
    final today = dayKey(_now);
    final cpw = costPerWear(own, days.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('In your wardrobe'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I own this'),
          subtitle: const Text(
            'Items you do not own stay on your wishlist, and can still go on outfit boards.',
          ),
          value: own != null,
          onChanged: _toggle,
        ),
        if (own != null) ...[
          Row(
            children: [
              Expanded(
                child: PaperField(
                  controller: _price,
                  label: 'Price paid',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _save(),
                ),
              ),
              const SizedBox(width: Space.m),
              SizedBox(
                width: 110,
                child: PaperField(
                  controller: _currency,
                  label: 'Currency',
                  maxLength: 3,
                  onChanged: (_) => _save(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text(
            days.isEmpty
                ? 'Not worn yet.'
                : 'Worn ${days.length} ${days.length == 1 ? 'day' : 'days'}, last on ${days.first}.',
          ),
          Text(
            cpw != null
                ? 'Cost per wear: ${money(cpw, own.currency)}.'
                : own.price == null
                ? 'Add the price paid to see cost per wear.'
                : 'Cost per wear appears after the first wear.',
            style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (!days.contains(today))
                PaperButton(
                  label: 'Wore it today',
                  icon: Icons.checkroom_outlined,
                  compact: true,
                  onPressed: () {
                    widget.repository.logWear([widget.product.id], today);
                    FeedbackScope.of(context).play(Cue.success);
                    setState(() {});
                  },
                )
              else
                PaperButton(
                  label: 'Undo today',
                  icon: Icons.undo,
                  compact: true,
                  onPressed: () {
                    widget.repository.unlogWear(widget.product.id, today);
                    FeedbackScope.of(context).play(Cue.toggle);
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
