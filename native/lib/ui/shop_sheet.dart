import 'package:flutter/material.dart';

import '../data/settings_store.dart';
import '../domain/screenshot_text.dart';
import '../domain/product.dart';
import '../domain/shops.dart';
import 'paper.dart';

/// Where to shop: search Amazon, eBay and others, go to any address, or
/// return to a shop already in the catalog. With [screenshot], it starts
/// from the words, price and links read from a screenshot.
class ShopSheet extends StatefulWidget {
  const ShopSheet({
    super.key,
    required this.settings,
    required this.onOpen,
    this.initialQuery = '',
    this.yourShops = const [],
    this.screenshot,
    this.onScreenshot,
  });
  final SettingsStore settings;
  final void Function(Uri) onOpen;
  final String initialQuery;
  final List<String> yourShops;
  final ScreenshotText? screenshot;

  /// Reads a screenshot; left out when it is already showing one.
  final VoidCallback? onScreenshot;
  @override
  State<ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<ShopSheet> {
  late final _query = TextEditingController(text: widget.screenshot?.query ?? widget.initialQuery);
  final _address = TextEditingController();
  late String _amazon = widget.settings.get<String>('shop.amazon') ?? amazonSites.first;
  late String _ebay = widget.settings.get<String>('shop.ebay') ?? ebaySites.first;
  String? _addressError;

  @override
  void dispose() {
    _query.dispose();
    _address.dispose();
    super.dispose();
  }

  void _open(Uri uri) {
    Navigator.pop(context);
    widget.onOpen(uri);
  }

  void _search(ShopSearch shop) {
    final q = _query.text.trim();
    final example = shop.search('x');
    _open(q.isEmpty ? Uri.https(example.host, '/') : shop.search(q));
  }

  Widget _site(String value, List<String> sites, String key, void Function(String) set) =>
      DropdownButton<String>(
        value: value,
        isDense: true,
        items: [for (final s in sites) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) {
          if (v == null) return;
          widget.settings.set(key, v);
          setState(() => set(v));
        },
      );

  @override
  Widget build(BuildContext context) {
    final shot = widget.screenshot;
    final shops = shopSearches(amazon: _amazon, ebay: _ebay);
    return PaperSheet(
      maxWidth: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              shot == null ? 'Shop in Vastra' : 'From your screenshot',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.xs),
            const Text(
              'Browse and sign in to any shop. On a product page, tap Save to Vastra and Vastra reads what is on the screen. Sign-ins go to the shop and stay in Vastra’s browser on this device.',
              style: TextStyle(color: Tone.inkSoft, fontSize: 12.5),
            ),
            if (shot != null) ...[
              const SizedBox(height: Space.l),
              if (shot.candidates.isEmpty)
                const Text('No product words were found. Type what to look for.')
              else ...[
                const Text(
                  'Words found. Tap to add or remove them from the search.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final c in shot.candidates)
                      FilterChip(
                        label: Text(c, overflow: TextOverflow.ellipsis),
                        selected: _query.text.contains(c),
                        onSelected: (on) => setState(() {
                          _query.text = on
                              ? '${_query.text} $c'.trim()
                              : _query.text.replaceFirst(c, '').replaceAll(RegExp(r'\s+'), ' ').trim();
                        }),
                      ),
                  ],
                ),
              ],
              if (shot.price case final price?)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Text(
                    'Price in the screenshot: ${Offer(seller: '', url: '', price: price.$1, currency: price.$2).priceText}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              for (final link in shot.links.take(3))
                Align(
                  alignment: Alignment.centerLeft,
                  child: PaperButton(
                    label: 'Open ${link.host}',
                    icon: Icons.link,
                    compact: true,
                    onPressed: () => _open(link),
                  ),
                ),
            ],
            const SizedBox(height: Space.l),
            PaperField(
              controller: _query,
              label: 'What are you looking for?',
              prefixIcon: Icons.search,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(shops.first),
            ),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final (i, s) in shops.indexed)
                  i == 0
                      ? CopperButton(
                          label: s.name,
                          icon: Icons.search,
                          compact: true,
                          onPressed: () => _search(s),
                        )
                      : PaperButton(label: s.name, compact: true, onPressed: () => _search(s)),
              ],
            ),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.l,
              runSpacing: Space.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Amazon: ', style: TextStyle(fontSize: 12.5)),
                    _site(_amazon, amazonSites, 'shop.amazon', (v) => _amazon = v),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('eBay: ', style: TextStyle(fontSize: 12.5)),
                    _site(_ebay, ebaySites, 'shop.ebay', (v) => _ebay = v),
                  ],
                ),
              ],
            ),
            if (widget.yourShops.isNotEmpty) ...[
              const SizedBox(height: Space.l),
              const Text('Your shops', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final host in widget.yourShops)
                    PaperButton(label: host, compact: true, onPressed: () => _open(Uri.https(host, '/'))),
                ],
              ),
            ],
            const SizedBox(height: Space.l),
            PaperField(
              controller: _address,
              label: 'Or go to a shop’s address',
              hint: 'zara.com',
              prefixIcon: Icons.public,
              error: _addressError,
              keyboardType: TextInputType.url,
              onSubmitted: (v) {
                final uri = shopAddress(v);
                uri == null
                    ? setState(() => _addressError = 'Type an address such as zara.com.')
                    : _open(uri);
              },
            ),
            const SizedBox(height: Space.m),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              alignment: WrapAlignment.end,
              children: [
                if (widget.onScreenshot != null)
                  PaperButton(
                    label: 'From a screenshot',
                    icon: Icons.document_scanner_outlined,
                    compact: true,
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onScreenshot!();
                    },
                  ),
                PaperButton(label: 'Close', compact: true, onPressed: () => Navigator.pop(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
