import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/catalog_data.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import '../domain/product_importer.dart';

const olive = Color(0xff344330);
const paper = Color(0xfffaf9f6);

class VastraApp extends StatelessWidget {
  const VastraApp({super.key, required this.data, required this.repository});
  final CatalogData data;
  final CatalogRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vastra',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: olive, surface: paper),
      appBarTheme: const AppBarTheme(backgroundColor: paper, foregroundColor: olive),
      cardTheme: const CardThemeData(color: Color(0xfff0f1e9), elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xffd8dece)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: olive, foregroundColor: Colors.white),
      ),
    ),
    home: Home(data: data, repository: repository),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.data, required this.repository});
  final CatalogData data;
  final CatalogRepository repository;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;
  String _query = '',
      _category = 'All discoveries',
      _currency = 'All currencies',
      _sort = 'Curated order',
      _collection = 'All collections',
      _sellerKind = 'All sellers';
  bool _samples = true;
  final _search = TextEditingController();
  final Set<String> _comparison = {};
  late List<CatalogEntry> _entries;
  @override
  void initState() {
    super.initState();
    _entries = widget.repository.readAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _entries = widget.repository.readAll();
  });
  List<Product> get _all {
    final products = {for (final p in widget.data.samples) p.id: p};
    for (final e in _entries) {
      products[e.product.id] = e.product;
    }
    return [
      ..._entries.where((e) => !e.product.sample).map((e) => e.product),
      ...products.values.where((p) => p.sample),
    ];
  }

  String? _saved(Product p) => _entries.where((e) => e.product.id == p.id).firstOrNull?.collection;
  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _write(void Function() action) {
    try {
      action();
      _reload();
    } on Object {
      _message('Your change could not be saved. Please try again.');
    }
  }

  Future<void> _open(String value) async {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No browser');
      }
    } on Object {
      _message('Could not open the link. Copy it from the product page instead.');
    }
  }

  void _save(Product p, [String collection = 'My edit']) => _write(() {
    if (_saved(p) != null) {
      widget.repository.unsave(p);
    } else {
      widget.repository.save(p, collection);
    }
  });
  void _toggleCompare(Product p) {
    if (!_comparison.contains(p.id) && _comparison.length >= 4) {
      _message('Compare up to four products at a time.');
      return;
    }
    setState(() {
      if (!_comparison.remove(p.id)) _comparison.add(p.id);
    });
  }

  Future<void> _import([String initial = '']) async {
    final product = await showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportDialog(
        importer: ProductImporter(widget.data.retailers),
        repository: widget.repository,
        initial: initial,
      ),
    );
    if (!mounted || product == null) return;
    _reload();
    await _detail(product);
  }

  Future<void> _detail(Product product) async {
    final collection = TextEditingController(text: _saved(product) ?? 'My edit');
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'A CLOSER LOOK',
                              style: TextStyle(letterSpacing: 2, fontSize: 11, color: olive),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close product',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 230,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ProductPhoto(product),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        product.brand,
                        style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: olive),
                      ),
                      const SizedBox(height: 8),
                      Text(product.name, style: const TextStyle(fontFamily: 'Lora', fontSize: 30)),
                      const SizedBox(height: 12),
                      Text(
                        product.description.isEmpty
                            ? 'No description was provided by the source.'
                            : product.description,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          Chip(label: Text(product.category)),
                          if (product.color != null) Chip(label: Text(product.color!)),
                        ],
                      ),
                      _fact('Material / formulation', product.material ?? 'Not provided by seller'),
                      _fact(
                        'Sizes listed',
                        product.sizes.isEmpty ? 'Check with seller' : product.sizes.join(' · '),
                      ),
                      _fact('Shipping, taxes and duties', 'Not included — confirm at checkout'),
                      _fact(
                        'Quality evidence',
                        product.sample
                            ? 'Illustrative sample only'
                            : 'Seller-provided; not independently verified',
                      ),
                      const SizedBox(height: 14),
                      ...product.offers.map(
                        (o) => Card(
                          child: ListTile(
                            title: Text(o.priceText, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${o.seller} · ${o.availability}'),
                            trailing: o.url.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'View original offer',
                                    onPressed: () => _open(o.url),
                                    icon: const Icon(Icons.north_east),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        product.sample
                            ? 'Sample imagery, specifications and pricing are illustrative. This is not a live listing.'
                            : 'Extracted ${DateTime.tryParse(product.checkedAt)?.toLocal().toString() ?? product.checkedAt}. Price and stock can change. Missing facts remain unknown.',
                        style: const TextStyle(fontSize: 12, color: Color(0xff626e57)),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: collection,
                        enabled: _saved(product) == null,
                        maxLength: 60,
                        decoration: const InputDecoration(labelText: 'Collection name'),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              _save(product, collection.text.trim().isEmpty ? 'My edit' : collection.text);
                              update(() {});
                            },
                            icon: Icon(_saved(product) == null ? Icons.favorite_border : Icons.favorite),
                            label: Text(
                              _saved(product) == null ? 'Save to collection' : 'Remove from collection',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              _toggleCompare(product);
                              update(() {});
                            },
                            icon: Icon(_comparison.contains(product.id) ? Icons.check : Icons.add),
                            label: const Text('Compare'),
                          ),
                        ],
                      ),
                      if (!product.sample) ...[
                        const Divider(height: 30),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _open(product.sourceUrl),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Original product'),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: product.sourceUrl));
                                _message('Product link copied.');
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy link'),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _import(product.sourceUrl);
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh details'),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Remove this product?'),
                                    content: const Text(
                                      'This removes the product from your catalog and its collection.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && dialogContext.mounted) {
                                  try {
                                    widget.repository.remove(product.id);
                                    setState(() {
                                      _comparison.remove(product.id);
                                      _entries = widget.repository.readAll();
                                    });
                                    Navigator.pop(dialogContext);
                                  } on Object {
                                    _message('The product could not be removed.');
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      collection.dispose();
    }
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xff626e57), fontSize: 12)),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
  void _compare() {
    final products = _all.where((p) => _comparison.contains(p.id)).toList();
    final rows = <(String, String Function(Product))>[
      ('Price', (p) => p.displayOffer?.priceText ?? 'Unknown'),
      ('Category', (p) => p.category),
      ('Material', (p) => p.material ?? 'Not provided'),
      ('Color / size', (p) => p.color ?? 'Not provided'),
      ('Evidence', (p) => p.sample ? 'Sample data' : 'Seller-provided'),
      ('Stock', (p) => p.displayOffer?.availability ?? 'Unknown'),
    ];
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'A little perspective.',
                          style: TextStyle(fontFamily: 'Lora', fontSize: 30),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close comparison',
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Independent selections, not verified exact matches. Prices stay in their original currencies and exclude shipping, taxes and duties.',
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        const DataColumn(label: Text('Detail')),
                        ...products.map(
                          (p) => DataColumn(label: SizedBox(width: 180, child: Text(p.name, maxLines: 3))),
                        ),
                      ],
                      rows: [
                        for (final row in rows)
                          DataRow(
                            cells: [
                              DataCell(Text(row.$1)),
                              ...products.map((p) => DataCell(SizedBox(width: 180, child: Text(row.$2(p))))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _about() => showAboutDialog(
    context: context,
    applicationName: 'Vastra',
    applicationVersion: '0.2.0',
    applicationIcon: const Icon(Icons.spa_outlined, size: 38, color: olive),
    children: [
      const Text(
        'A standalone space for fashion, footwear, accessories, beauty, fragrance and personal care. Your native catalog stays on this device in an app-private SQLite database. No account is required. Native and hosted-web catalogs are currently separate.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Search covers the inspiration catalog and your imported products. The seller directory is curated. Live multi-store search, automated seller discovery and optional AI models are planned; no AI service is connected or billed.',
      ),
      TextButton(
        onPressed: () => _open('https://github.com/sudharamachandranrajeev/vastra'),
        child: const Text('Source code and roadmap'),
      ),
    ],
  );
  void _navigate(int tab) => setState(() {
    _tab = tab;
    _query = '';
    _search.clear();
  });
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    final collections = _entries.map((e) => e.collection).whereType<String>().toSet().toList()..sort();
    final currencies =
        _all.expand((p) => p.offers.map((o) => o.currency)).whereType<String>().toSet().toList()..sort();
    var products = _all
        .where(
          (p) =>
              p.matches(_query, _category) &&
              (_samples || !p.sample) &&
              (_currency == 'All currencies' || p.offers.any((o) => o.currency == _currency)),
        )
        .toList();
    if (_tab == 1) products = products.where((p) => !p.sample).toList();
    if (_tab == 3) {
      products = products
          .where((p) => _saved(p) != null && (_collection == 'All collections' || _saved(p) == _collection))
          .toList();
    }
    if (_sort == 'Name A–Z') products.sort((a, b) => a.name.compareTo(b.name));
    if (_sort == 'Price: low to high' && _currency != 'All currencies') {
      double amount(Product p) {
        final prices =
            p.offers.where((o) => o.currency == _currency && o.price != null).map((o) => o.price!).toList()
              ..sort();
        return prices.firstOrNull ?? double.infinity;
      }

      products.sort((a, b) => amount(a).compareTo(amount(b)));
    }
    final content = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(wide ? 36 : 20, 28, wide ? 36 : 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_tab == 0)
                  Container(
                    padding: EdgeInsets.all(wide ? 34 : 24),
                    decoration: BoxDecoration(
                      color: const Color(0xffeef0e5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GOOD FINDS. GREAT POSSIBILITIES.',
                          style: TextStyle(letterSpacing: 2, fontSize: 11, color: olive),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'A world of good finds.\nAn edit that’s you.',
                          style: TextStyle(
                            fontFamily: 'Lora',
                            fontSize: wide ? 46 : 34,
                            height: 1.12,
                            color: olive,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Discover fashion, beauty, and the people behind them.\nBring your favorites together, beautifully.',
                        ),
                        const SizedBox(height: 14),
                        const Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            Text('Global discovery'),
                            Text('Original currencies'),
                            Text('Your catalog, on your device'),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    _tab == 1
                        ? 'Your finds, together.'
                        : _tab == 2
                        ? 'Meet your next good source.'
                        : 'A little more you.',
                    style: const TextStyle(fontFamily: 'Lora', fontSize: 34, color: olive),
                  ),
                const SizedBox(height: 24),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: _tab == 2
                        ? 'Search sellers, countries or specialties'
                        : 'Search your finds or paste a product link',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                  onSubmitted: (value) {
                    if (value.startsWith('https://')) _import(value);
                  },
                ),
                const SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in widget.data.categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) => setState(() => _category = category),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_tab != 2)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: _currency,
                        items: [
                          'All currencies',
                          ...currencies,
                        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                        onChanged: (v) => setState(() {
                          _currency = v!;
                          if (v == 'All currencies') _sort = 'Curated order';
                        }),
                      ),
                      DropdownButton<String>(
                        value: _sort,
                        items: [
                          'Curated order',
                          'Name A–Z',
                          if (_currency != 'All currencies') 'Price: low to high',
                        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                        onChanged: (v) => setState(() => _sort = v!),
                      ),
                      if (_tab == 0)
                        FilterChip(
                          label: const Text('Include samples'),
                          selected: _samples,
                          onSelected: (v) => setState(() => _samples = v),
                        ),
                      if (_tab == 3)
                        DropdownButton<String>(
                          value: collections.contains(_collection) ? _collection : 'All collections',
                          items: [
                            'All collections',
                            ...collections,
                          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                          onChanged: (v) => setState(() => _collection = v!),
                        ),
                    ],
                  ),
                if (_tab == 2)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in [
                        'All sellers',
                        'Independent',
                        'Marketplace',
                        'Wholesale',
                        'Retail',
                        'Directory',
                      ])
                        ChoiceChip(
                          label: Text(kind),
                          selected: _sellerKind == kind,
                          onSelected: (_) => setState(() => _sellerKind = kind),
                        ),
                    ],
                  ),
                const SizedBox(height: 14),
                Text(
                  _tab == 2
                      ? 'Curated sources with public website contacts. Listings are not endorsements.'
                      : '${products.length} finds · Prices exclude shipping, taxes and duties.',
                  style: const TextStyle(fontSize: 12, color: Color(0xff626e57)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        if (_tab == 2)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 20),
            sliver: SliverList.list(
              children: widget.data.sellers
                  .where(
                    (s) =>
                        (_sellerKind == 'All sellers' || s['kind'] == _sellerKind) &&
                        (_category == 'All discoveries' || (s['categories'] as List).contains(_category)) &&
                        '${s['name']} ${s['description']} ${s['country']}'.toLowerCase().contains(
                          _query.trim().toLowerCase(),
                        ),
                  )
                  .map(
                    (s) => Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['name'] as String,
                              style: const TextStyle(fontFamily: 'Lora', fontSize: 26),
                            ),
                            Text(
                              '${s['country']} · ${s['kind']}',
                              style: const TextStyle(color: olive, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Text(s['description'] as String),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _open(s['url'] as String),
                                  icon: const Icon(Icons.north_east),
                                  label: const Text('Explore source'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _open(s['contact'] as String),
                                  icon: const Icon(Icons.contact_page_outlined),
                                  label: const Text('Public contact'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          )
        else if (products.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const Icon(Icons.explore_outlined, size: 44, color: olive),
                  const SizedBox(height: 18),
                  Text(
                    _tab == 1
                        ? 'Your next good find starts here'
                        : _tab == 3
                        ? 'Make room for your favorites'
                        : 'No finds match this search',
                    style: const TextStyle(fontFamily: 'Lora', fontSize: 26),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Import a product link, save a favorite, or try a broader search.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Add a product link'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 1200
                    ? 4
                    : constraints.crossAxisExtent >= 760
                    ? 3
                    : constraints.crossAxisExtent < 300
                    ? 1
                    : 2;
                return SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final p = products[index];
                    return ProductCard(
                      product: p,
                      saved: _saved(p) != null,
                      compared: _comparison.contains(p.id),
                      onOpen: () => _detail(p),
                      onSave: () => _save(p),
                      onCompare: () => _toggleCompare(p),
                    );
                  }, childCount: products.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: wide ? 420 : 370,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 18,
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(wide ? 36 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_query.trim().isNotEmpty && _tab != 2) ...[
                  const Text(
                    'KEEP EXPLORING',
                    style: TextStyle(letterSpacing: 2, fontSize: 11, color: olive),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _open(
                          Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': _query}).toString(),
                        ),
                        icon: const Icon(Icons.north_east),
                        label: const Text('Google Shopping'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _open(Uri.https('www.etsy.com', '/search', {'q': _query}).toString()),
                        icon: const Icon(Icons.north_east),
                        label: const Text('Etsy'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'Inspiration samples are illustrative, not live offers. Import a link to build your real catalog.',
                  style: TextStyle(fontSize: 12, color: Color(0xff626e57)),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'One link. All the lovely details.',
                          style: TextStyle(fontFamily: 'Lora', fontSize: 28),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Bring a product into Vastra. Its source, details and original currency stay with it.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _import,
                          icon: const Icon(Icons.add_link),
                          label: const Text('Add a product link'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'vastra.',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -1.5),
        ),
        actions: [
          IconButton(tooltip: 'About Vastra', onPressed: _about, icon: const Icon(Icons.info_outline)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.add, size: 18),
              label: Text(wide ? 'Add a product link' : 'Add link'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _navigate,
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.explore_outlined), label: Text('Discover')),
                  NavigationRailDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    label: Text('My catalog'),
                  ),
                  NavigationRailDestination(icon: Icon(Icons.storefront_outlined), label: Text('Sellers')),
                  NavigationRailDestination(icon: Icon(Icons.bookmarks_outlined), label: Text('Collections')),
                ],
              ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _navigate,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Discover'),
                NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Catalog'),
                NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Sellers'),
                NavigationDestination(icon: Icon(Icons.bookmarks_outlined), label: 'Collections'),
              ],
            ),
      floatingActionButton: _comparison.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _compare,
              icon: const Icon(Icons.compare_arrows),
              label: Text('Compare ${_comparison.length}'),
            ),
    );
  }
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto(this.product, {super.key});
  final Product product;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
      color: const Color(0xffe8ebdf),
      alignment: Alignment.center,
      child: const Icon(Icons.checkroom_outlined, size: 42, color: Color(0xff889776)),
    );
    if (product.sample) {
      return Image.asset(
        'assets/images/${product.id}.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, error, stack) => fallback(),
      );
    }
    return product.images.isEmpty
        ? fallback()
        : Image.network(
            product.images.first,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, error, stack) => fallback(),
          );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.saved,
    required this.compared,
    required this.onOpen,
    required this.onSave,
    required this.onCompare,
  });
  final Product product;
  final bool saved, compared;
  final VoidCallback onOpen, onSave, onCompare;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                label: 'View ${product.name}',
                button: true,
                child: InkWell(onTap: onOpen, child: ProductPhoto(product)),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: paper.withValues(alpha: .93),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    product.sample ? 'SAMPLE EDIT' : 'YOUR DISCOVERY',
                    style: const TextStyle(fontSize: 9, letterSpacing: 1, color: olive),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: saved ? 'Unsave ${product.name}' : 'Save ${product.name}',
                  onPressed: onSave,
                  icon: Icon(saved ? Icons.favorite : Icons.favorite_border, size: 18),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 6,
                child: ActionChip(
                  label: Text(compared ? 'Added' : 'Compare', style: const TextStyle(fontSize: 10)),
                  avatar: Icon(compared ? Icons.check : Icons.add, size: 14),
                  onPressed: onCompare,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        product.brand,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, letterSpacing: 1, color: olive),
      ),
      TextButton(
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 40),
        ),
        onPressed: onOpen,
        child: Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xff283029), fontSize: 13),
        ),
      ),
      Text(
        product.displayOffer?.priceText ?? 'Price unavailable',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: olive, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        product.sample ? 'Illustrative price' : 'Source price · excludes delivery',
        maxLines: 1,
        style: const TextStyle(fontSize: 10, color: Color(0xff626e57)),
      ),
    ],
  );
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.importer, required this.repository, this.initial = ''});
  final ProductImporter importer;
  final CatalogRepository repository;
  final String initial;
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  late final TextEditingController _url = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final product = await widget.importer.fetch(_url.text);
      if (!mounted) return;
      final stored = widget.repository.importProduct(product);
      Navigator.pop(context, stored);
    } on ImportFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The product could not be saved. Your existing catalog has not been reset.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('A link to your next good find.'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Paste a product page. We’ll gather its details into your local catalog. Importing an existing link refreshes its details and preserves its collection.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _url,
                autofocus: true,
                enabled: !_busy,
                maxLength: 2048,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Product link',
                  hintText: 'https://www.store.com/product/…',
                ),
                onSubmitted: (_) {
                  if (!_busy) _submit();
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 10),
                      Text('Gathering product details…'),
                    ],
                  ),
                ),
              const SizedBox(height: 15),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Eligible stores and limitations', style: TextStyle(fontSize: 13)),
                children: [
                  Text(widget.importer.retailers.join(' · '), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text(
                    'Stores can block automated access or omit product data. Shipping, taxes, duties, quality and returns must be confirmed with the seller. No AI key is needed.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.add_link),
          label: const Text('Import product'),
        ),
      ],
    ),
  );
}
