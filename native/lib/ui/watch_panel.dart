import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/product.dart';
import '../domain/watching.dart';
import 'feedback.dart';
import 'paper.dart';

/// Price history, freshness and the watch controls for one imported item.
class WatchPanel extends StatefulWidget {
  const WatchPanel({
    super.key,
    required this.product,
    required this.repository,
    required this.onWatchStarted,
    this.now,
  });
  final Product product;
  final CatalogRepository repository;

  /// Called when the first watch starts, so the app can ask to notify.
  final VoidCallback onWatchStarted;

  /// Fixed clock for tests.
  final DateTime? now;
  @override
  State<WatchPanel> createState() => _WatchPanelState();
}

class _WatchPanelState extends State<WatchPanel> {
  late Watch? _watch = widget.repository.watchFor(widget.product.id);
  late final _value = TextEditingController(text: _format(_watch?.value));

  static String _format(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _set(Watch? watch) {
    FeedbackScope.of(context).play(Cue.toggle);
    if (watch == null) {
      widget.repository.unwatch(widget.product.id);
    } else {
      final first = _watch == null && widget.repository.watches().isEmpty;
      widget.repository.setWatch(watch);
      if (first) widget.onWatchStarted();
    }
    setState(() => _watch = watch);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final now = (widget.now ?? DateTime.now()).toUtc();
    final watch = _watch;
    final variants = [for (final v in p.variants) variantKey(v)].where((k) => k.isNotEmpty).toSet().toList();
    final key = watch?.variant ?? '';
    final points = widget.repository.history(p.id).where((h) => h.ok && h.variant == key).toList();
    final fresh = widget.repository.freshness(p.id);
    final lastOk = fresh.lastOk ?? DateTime.tryParse(p.checkedAt);
    final stale = staleReason(lastOk: lastOk, lastFailed: fresh.lastFailed, now: now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Price and stock'),
        const SizedBox(height: Space.m),
        _HistoryLine(points: points),
        if (lastOk != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            'Prices ${checkedAgo(lastOk, now)}.',
            style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5),
          ),
        ],
        if (stale != null) ...[
          const SizedBox(height: Space.s),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Tone.error),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(stale, style: const TextStyle(color: Tone.error, fontSize: 12.5)),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Watch this item'),
          subtitle: const Text('Only the changes you choose. No other notifications, ever.'),
          value: watch != null,
          onChanged: (on) => _set(on ? Watch(productId: p.id) : null),
        ),
        if (watch != null) ...[
          if (variants.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: variants.contains(watch.variant) ? watch.variant : '',
              decoration: const InputDecoration(labelText: 'Size and colour'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Any size or colour')),
                for (final v in variants) DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) => _set(watch.copyWith(variant: v ?? '')),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Price drops'),
            value: watch.price,
            onChanged: (v) => _set(watch.copyWith(price: v)),
          ),
          if (watch.price)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (rule, label) in [
                    (PriceRule.anyDrop, 'Any drop'),
                    (PriceRule.percent, 'By at least %'),
                    (PriceRule.target, 'At or below'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: watch.rule == rule,
                      onSelected: (_) => _set(watch.copyWith(rule: rule)),
                    ),
                  if (watch.rule != PriceRule.anyDrop)
                    SizedBox(
                      width: 140,
                      child: PaperField(
                        controller: _value,
                        label: watch.rule == PriceRule.percent ? 'Percent' : 'Price',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (text) {
                          final v = double.tryParse(text.replaceAll(',', '.'));
                          if (v != null && v > 0) {
                            widget.repository.setWatch(watch.copyWith(value: v));
                            _watch = watch.copyWith(value: v);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Back in stock'),
            value: watch.stock,
            onChanged: (v) => _set(watch.copyWith(stock: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tell me at once'),
            subtitle: const Text(
              'Checks hourly and notifies straight away, for things that sell out fast. Otherwise changes arrive in one daily digest.',
            ),
            value: watch.immediate,
            onChanged: (v) => _set(watch.copyWith(immediate: v)),
          ),
        ],
      ],
    );
  }
}

/// Lowest, highest and current price, with a small line of the history.
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.points});
  final List<PricePoint> points;

  @override
  Widget build(BuildContext context) {
    final currency = points
        .lastWhere((p) => p.price != null, orElse: () => points.lastOrNull ?? _none)
        .currency;
    final priced = points.where((p) => p.price != null && p.currency == currency).toList();
    if (priced.length < 2) {
      return const Text(
        'Price history starts with the next refresh.',
        style: TextStyle(color: Tone.inkSoft, fontSize: 12.5),
      );
    }
    final low = priced.reduce((a, b) => a.price! <= b.price! ? a : b);
    final high = priced.reduce((a, b) => a.price! >= b.price! ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Price history, ${priced.length} checks',
          child: SizedBox(
            height: 48,
            child: CustomPaint(painter: _Spark([for (final p in priced) p.price!])),
          ),
        ),
        const SizedBox(height: Space.s),
        Text(
          'Low ${low.priceText} · High ${high.priceText} · Now ${priced.last.priceText}',
          style: const TextStyle(fontSize: 12.5),
        ),
      ],
    );
  }
}

final _none = PricePoint(productId: '', seller: '', variant: '', checkedAt: DateTime(2000), ok: false);

class _Spark extends CustomPainter {
  _Spark(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce((a, b) => a < b ? a : b), high = values.reduce((a, b) => a > b ? a : b);
    final span = high - low == 0 ? 1 : high - low;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - 4 - (size.height - 8) * (values[i] - low) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Tone.copper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values;
}
