import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/catalog_data.dart';
import '../data/catalog_repository.dart';
import '../data/share_intake.dart';
import '../domain/catalog_export.dart';
import '../domain/categorizer.dart';
import '../domain/product.dart';
import '../domain/product_importer.dart';
import '../domain/recommender.dart';
import 'feedback.dart';
import 'paper.dart';

class VastraApp extends StatelessWidget {
  const VastraApp({super.key, required this.data, required this.repository, this.intake, this.feedback, this.importer});
  final CatalogData data;
  final CatalogRepository repository;
  final ShareIntake? intake;
  final UiFeedback? feedback;

  /// Replaces network imports in tests.
  final ProductImporter Function(Categorizer categorizer)? importer;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vastra',
    debugShowCheckedModeBanner: false,
    theme: paperTheme(),
    builder: (context, child) => FeedbackScope(
      feedback: feedback ?? UiFeedback.silent(),
      child: ToastHost(child: child!),
    ),
    home: Home(data: data, repository: repository, intake: intake ?? ShareIntake(), importer: importer),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.data, required this.repository, required this.intake, this.importer});
  final CatalogData data;
  final CatalogRepository repository;
  final ShareIntake intake;
  final ProductImporter Function(Categorizer categorizer)? importer;
  @override
  State<Home> createState() => _HomeState();
}

const _tabs = ['Discover', 'My catalog', 'Sellers', 'Collections'];
const _tabIcons = [Icons.explore_outlined, Icons.inventory_2_outlined, Icons.storefront_outlined, Icons.bookmarks_outlined];

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int _tab = 0, _page = 0;
  String _query = '',
      _category = 'All discoveries',
      _currency = 'All currencies',
      _sort = 'Curated order',
      _collection = 'All collections',
      _sellerKind = 'All sellers';
  bool _samples = true;
  String? _copiedLink, _dismissedLink;
  final _search = TextEditingController();
  final Set<String> _comparison = {};
  late List<CatalogEntry> _entries;
  late Recommender _recommender;
  StreamSubscription<String>? _shares;
  Future<void> _shareQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entries = widget.repository.readAll();
    _recommender = Recommender(_all);
    _shares = widget.intake.shared.listen(_receive);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await widget.intake.initial();
      if (initial != null) _receive(initial);
      unawaited(_checkClipboard());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shares?.cancel());
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkClipboard());
  }

  bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// On desktop, "Copy link" is how other apps share; offer the copied link.
  /// Android shows a notice whenever the clipboard is read, so it relies on
  /// the share sheet instead.
  Future<void> _checkClipboard() async {
    if (!_desktop) return;
    try {
      final link = sharedLink((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '');
      if (link == null || link == _dismissedLink || !mounted) return;
      final known = _entries.any((e) => e.product.sourceUrl == ProductImporter().validate(link).toString());
      setState(() => _copiedLink = known ? null : link);
    } on Object {
      /* Not a usable link; nothing to offer. */
    }
  }

  void _receive(String text) {
    _shareQueue = _shareQueue.then((_) => mounted ? _import(text, true) : null);
  }

  void _reload() => setState(() {
    _entries = widget.repository.readAll();
    _recommender = Recommender(_all);
  });

  List<Product> get _all {
    final products = {for (final p in widget.data.samples) p.id: p};
    for (final e in _entries) {
      products[e.product.id] = e.product;
    }
    return [..._entries.where((e) => !e.product.sample).map((e) => e.product), ...products.values.where((p) => p.sample)];
  }

  Categorizer get _categorizer => Categorizer([
    for (final e in _entries)
      if (e.product.categorySource == 'user') (e.product.text, e.product.category, e.product.productType),
  ]);

  String? _saved(Product p) => _entries.where((e) => e.product.id == p.id).firstOrNull?.collection;
  void _toast(ToastKind kind, String message) {
    if (mounted) ToastHost.of(context).show(kind, message);
  }

  bool _write(void Function() action) {
    try {
      action();
      _reload();
      return true;
    } on Object {
      _toast(ToastKind.error, 'Your change could not be saved. Please try again.');
      return false;
    }
  }

  Future<void> _open(String value) async {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'https' || uri.host.isEmpty || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No browser');
      }
    } on Object {
      _toast(ToastKind.warning, 'Could not open the link. Copy it from the product page instead.');
    }
  }

  void _save(Product p, [String collection = 'My edit']) {
    final saved = _saved(p) != null;
    if (_write(() => saved ? widget.repository.unsave(p) : widget.repository.save(p, collection))) {
      _toast(saved ? ToastKind.info : ToastKind.success, saved ? 'Removed from $collection.' : 'Saved to $collection.');
    }
  }

  void _toggleCompare(Product p) {
    if (!_comparison.contains(p.id) && _comparison.length >= 4) {
      _toast(ToastKind.warning, 'Compare up to four products at a time.');
      return;
    }
    setState(() {
      if (!_comparison.remove(p.id)) _comparison.add(p.id);
    });
  }

  Future<void> _import([String initial = '', bool auto = false]) async {
    if (_copiedLink != null && initial == _copiedLink) setState(() => _dismissedLink = _copiedLink);
    final importer = widget.importer?.call(_categorizer) ?? ProductImporter(categorizer: _categorizer);
    final product = await showPaperDialog<Product>(
      context,
      dismissible: false,
      builder: (_) => ImportSheet(importer: importer, repository: widget.repository, initial: initial, auto: auto),
    );
    if (!mounted || product == null) return;
    _reload();
    _toast(
      product.extraction == 'link' ? ToastKind.info : ToastKind.success,
      product.extraction == 'link'
          ? 'Link saved. The store shared few details, so refresh it later.'
          : 'Added to your catalog as ${product.productType ?? product.category}.',
    );
    await _detail(product);
  }

  Future<void> _detail(Product product) => showPaperDialog<void>(
    context,
    builder: (dialogContext) => _ProductDetail(
      product: product,
      home: this,
      close: () => Navigator.pop(dialogContext),
    ),
  );

  Future<void> _remove(Product product, BuildContext dialogContext) async {
    final confirmed = await showPaperDialog<bool>(
      context,
      builder: (c) => PaperSheet(
        maxWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Confirm Delete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.s),
            const Text(
              'Are you sure you want to remove this product from your catalog and its collection?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PaperButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
                const SizedBox(width: Space.m),
                CopperButton(label: 'Delete', onPressed: () => Navigator.pop(c, true)),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !dialogContext.mounted) return;
    if (_write(() => widget.repository.remove(product.id))) {
      _comparison.remove(product.id);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      _toast(ToastKind.info, 'Removed from your catalog.');
    }
  }

  void _recategorize(Product product, String category, String? type) {
    if (_write(() => widget.repository.update(product.withCategory(category, type)))) {
      _toast(ToastKind.success, 'Moved to ${type ?? category}. Similar finds will follow.');
    }
  }

  void _compare() {
    final products = _all.where((p) => _comparison.contains(p.id)).toList();
    final rows = <(String, String Function(Product))>[
      ('Price', (p) => p.displayOffer?.priceText ?? 'Unknown'),
      ('Type', (p) => p.productType ?? p.category),
      ('Brand', (p) => p.brand),
      ('Material', (p) => p.material ?? 'Not provided'),
      ('Colour', (p) => p.color ?? 'Not provided'),
      ('Sizes', (p) => p.sizes.isEmpty ? 'Not provided' : p.sizes.join(' · ')),
      ('Rating', (p) => p.rating == null ? 'Not rated' : '${p.rating} (${p.reviewCount ?? '?'} reviews)'),
      ('Stock', (p) => p.displayOffer?.availability ?? 'Unknown'),
      ('Evidence', (p) => p.sample ? 'Sample data' : 'Seller-provided'),
    ];
    showPaperDialog<void>(
      context,
      builder: (c) => PaperSheet(
        maxWidth: 1100,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Side by side', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                  ),
                  PaperIconButton(icon: Icons.close, tooltip: 'Close comparison', onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: Space.s),
              const Text(
                'Independent selections, not verified exact matches. Prices stay in their original currencies and exclude shipping, taxes and duties.',
                style: TextStyle(color: Tone.inkSoft),
              ),
              const SizedBox(height: Space.xl),
              Paper(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(Tone.paperHigh),
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Tone.ink),
                    dividerThickness: 0.6,
                    columns: [
                      const DataColumn(label: Text('Detail')),
                      ...products.map((p) => DataColumn(label: SizedBox(width: 180, child: Text(p.name, maxLines: 3)))),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            DataCell(Text(row.$1, style: const TextStyle(color: Tone.inkSoft))),
                            ...products.map((p) => DataCell(SizedBox(width: 180, child: Text(row.$2(p))))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    final collections = _entries.map((e) => e.collection).whereType<String>().toSet().toList()..sort();
    await showPaperDialog<void>(
      context,
      builder: (c) => ExportSheet(
        products: [for (final e in _entries) if (!e.product.sample) e],
        collections: collections,
        onDone: (message, ok) => _toast(ok ? ToastKind.success : ToastKind.error, message),
      ),
    );
  }

  void _settings() {
    final feedback = FeedbackScope.of(context);
    showPaperDialog<void>(
      context,
      builder: (c) => PaperSheet(
        maxWidth: 520,
        child: ListenableBuilder(
          listenable: feedback,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                  PaperIconButton(icon: Icons.close, tooltip: 'Close settings', onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: Space.l),
              const SectionHeader('Feedback'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Soft sounds'),
                subtitle: const Text('Quiet chimes when you add, save or open things.'),
                value: feedback.sound,
                onChanged: (v) {
                  feedback.sound = v;
                  feedback.play(Cue.toggle);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Light haptics'),
                subtitle: const Text('A gentle tap on supported phones.'),
                value: feedback.haptics,
                onChanged: (v) {
                  feedback.haptics = v;
                  feedback.play(Cue.toggle);
                },
              ),
              const SizedBox(height: Space.l),
              const SectionHeader('About'),
              const SizedBox(height: Space.m),
              const Text(
                'Vastra 0.3.0. Fashion, footwear, accessories, beauty, fragrance and personal care, gathered from any store. Your catalog stays on this device. No account, no tracking, no ads, and never more than you asked for.',
              ),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  PaperButton(
                    label: 'Source code and roadmap',
                    icon: Icons.north_east,
                    compact: true,
                    onPressed: () => _open('https://github.com/sudharamachandranrajeev/vastra'),
                  ),
                  PaperButton(
                    label: 'Licences',
                    compact: true,
                    onPressed: () => showLicensePage(context: context, applicationName: 'Vastra', applicationVersion: '0.3.0'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(int tab) => setState(() {
    _tab = tab;
    _page = 0;
    _query = '';
    _search.clear();
  });

  List<Product> _visible() {
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
      products = products.where((p) => _saved(p) != null && (_collection == 'All collections' || _saved(p) == _collection)).toList();
    }
    if (_sort == 'Name A–Z') products.sort((a, b) => a.name.compareTo(b.name));
    if (_sort == 'Price: low to high' && _currency != 'All currencies') {
      double amount(Product p) {
        final prices = p.offers.where((o) => o.currency == _currency && o.price != null).map((o) => o.price!).toList()..sort();
        return prices.firstOrNull ?? double.infinity;
      }

      products.sort((a, b) => amount(a).compareTo(amount(b)));
    }
    return products;
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged, String label) => Semantics(
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.m),
      decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          dropdownColor: Tone.paper,
          borderRadius: BorderRadius.circular(Radii.s),
          icon: const Icon(Icons.expand_more, color: Tone.copper),
          style: const TextStyle(color: Tone.ink, fontFamily: 'Inter', fontSize: 13.5),
          items: options.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) {
            FeedbackScope.of(context).play(Cue.toggle);
            onChanged(v!);
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    final gutter = wide ? Space.huge - 16 : Space.l;
    final collections = _entries.map((e) => e.collection).whereType<String>().toSet().toList()..sort();
    final currencies = _all.expand((p) => p.offers.map((o) => o.currency)).whereType<String>().toSet().toList()..sort();
    final products = _visible();
    final perPage = wide ? 16 : 10;
    final pages = (products.length / perPage).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final shown = products.skip(page * perPage).take(perPage).toList();
    final liked = [
      ..._entries.where((e) => e.collection != null).map((e) => e.product),
      ..._entries.where((e) => !e.product.sample).map((e) => e.product),
    ];
    final picks = _tab == 0 && _query.isEmpty ? _recommender.forYou(liked, limit: 10) : const <Product>[];

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_copiedLink != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: AlertBanner(
              title: 'Copied link:',
              message: Uri.tryParse(_copiedLink!)?.host ?? _copiedLink!,
              icon: Icons.link,
              actions: [
                CopperButton(label: 'Add to catalog', compact: true, onPressed: () => _import(_copiedLink!)),
                PaperButton(
                  label: 'Not now',
                  compact: true,
                  onPressed: () => setState(() {
                    _dismissedLink = _copiedLink;
                    _copiedLink = null;
                  }),
                ),
              ],
            ),
          ),
        if (_tab == 0)
          Paper(
            level: 2,
            radius: Radii.m,
            padding: EdgeInsets.all(wide ? Space.xxl + 4 : Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RibbonBadge('GOOD FINDS'),
                const SizedBox(height: Space.l),
                Text(
                  'A world of good finds.\nAn edit that’s you.',
                  style: TextStyle(fontSize: wide ? 42 : 30, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -0.8),
                ),
                const SizedBox(height: Space.m),
                const Text(
                  'Share any product from any app or store. Vastra gathers the details, files it in the right place and finds more like it.',
                  style: TextStyle(color: Tone.inkSoft),
                ),
                const SizedBox(height: Space.l),
                Wrap(
                  spacing: Space.m,
                  runSpacing: Space.s,
                  children: [
                    CopperButton(label: 'Add a product link', icon: Icons.add_link, onPressed: _import),
                    if (_entries.any((e) => !e.product.sample))
                      PaperButton(label: 'Export catalog', icon: Icons.ios_share, onPressed: _export),
                  ],
                ),
              ],
            ),
          )
        else
          Text(
            switch (_tab) {
              1 => 'Your finds, together.',
              2 => 'Meet your next good source.',
              _ => 'A little more you.',
            },
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6),
          ),
        const SizedBox(height: Space.xl),
        PaperField(
          controller: _search,
          label: _tab == 2 ? 'Search sellers, countries or specialties' : 'Search your finds or paste a product link',
          prefixIcon: Icons.search,
          suffix: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close, color: Tone.copper),
                ),
          onChanged: (value) => setState(() {
            _query = value;
            _page = 0;
          }),
          onSubmitted: (value) {
            if (sharedLink(value) != null && RegExp(r'https?://|/').hasMatch(value)) _import(value);
          },
        ),
        const SizedBox(height: Space.l),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in widget.data.categories)
                Padding(
                  padding: const EdgeInsets.only(right: Space.s, bottom: Space.xs, top: Space.xs),
                  child: PaperButton(
                    label: category,
                    compact: true,
                    selected: _category == category,
                    cue: Cue.toggle,
                    onPressed: () => setState(() {
                      _category = category;
                      _page = 0;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        if (_tab != 2)
          Wrap(
            spacing: Space.m,
            runSpacing: Space.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _dropdown(_currency, ['All currencies', ...currencies], (v) => setState(() {
                _currency = v;
                if (v == 'All currencies') _sort = 'Curated order';
              }), 'Currency'),
              _dropdown(_sort, ['Curated order', 'Name A–Z', if (_currency != 'All currencies') 'Price: low to high'], (v) => setState(() => _sort = v), 'Sort'),
              if (_tab == 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _samples,
                      onChanged: (v) {
                        FeedbackScope.of(context).play(Cue.toggle);
                        setState(() => _samples = v!);
                      },
                    ),
                    const Text('Include samples'),
                  ],
                ),
              if (_tab == 3) _dropdown(_collection, ['All collections', ...collections], (v) => setState(() => _collection = v), 'Collection'),
            ],
          ),
        if (_tab == 2)
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final kind in ['All sellers', 'Independent', 'Marketplace', 'Wholesale', 'Retail', 'Directory'])
                PaperButton(
                  label: kind,
                  compact: true,
                  selected: _sellerKind == kind,
                  cue: Cue.toggle,
                  onPressed: () => setState(() => _sellerKind = kind),
                ),
            ],
          ),
        const SizedBox(height: Space.m),
        Text(
          _tab == 2
              ? 'Curated sources with public website contacts. Listings are not endorsements.'
              : '${products.length} finds · Prices exclude shipping, taxes and duties.',
          style: const TextStyle(fontSize: 12, color: Tone.inkSoft),
        ),
        if (picks.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader('Picked for you'),
          const SizedBox(height: Space.xs),
          const Text(
            'Like the things you saved and imported. Worked out on this device.',
            style: TextStyle(fontSize: 12, color: Tone.inkSoft),
          ),
          const SizedBox(height: Space.m),
          SimilarStrip(products: picks, onOpen: _detail),
        ],
        const SizedBox(height: Space.xl),
      ],
    );

    final sellers = widget.data.sellers
        .where(
          (s) =>
              (_sellerKind == 'All sellers' || s['kind'] == _sellerKind) &&
              (_category == 'All discoveries' || (s['categories'] as List).contains(_category)) &&
              '${s['name']} ${s['description']} ${s['country']}'.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();

    final body = CustomScrollView(
      key: PageStorageKey(_tab),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, Space.xl, gutter, 0),
          sliver: SliverToBoxAdapter(child: header),
        ),
        if (_tab == 2)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: SliverList.builder(
              itemCount: sellers.length,
              itemBuilder: (context, i) {
                final s = sellers[i];
                return Arrive(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.l),
                    child: Paper(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PaperAvatar(s['name'] as String),
                          const SizedBox(width: Space.l),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['name'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('${s['country']} · ${s['kind']}', style: const TextStyle(color: Tone.copper, fontSize: 12.5)),
                                const SizedBox(height: Space.m),
                                Text(s['description'] as String),
                                const SizedBox(height: Space.m),
                                Wrap(
                                  spacing: Space.s,
                                  runSpacing: Space.s,
                                  children: [
                                    PaperButton(label: 'Explore source', icon: Icons.north_east, compact: true, onPressed: () => _open(s['url'] as String)),
                                    PaperButton(label: 'Public contact', icon: Icons.contact_page_outlined, compact: true, onPressed: () => _open(s['contact'] as String)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else if (products.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: SliverToBoxAdapter(
              child: EmptyState(
                title: switch (_tab) {
                  1 => 'No Items Found',
                  3 => 'Make room for your favorites',
                  _ => 'No finds match this search',
                },
                message: 'Share a product from any app, paste a link, save a favorite, or try a broader search.',
                action: 'Add New Item',
                onAction: _import,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
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
                    final p = shown[index];
                    return Arrive(
                      key: ValueKey('${p.id}-$page'),
                      index: index,
                      child: ProductCard(
                        product: p,
                        saved: _saved(p) != null,
                        compared: _comparison.contains(p.id),
                        onOpen: () => _detail(p),
                        onSave: () => _save(p),
                        onCompare: () => _toggleCompare(p),
                      ),
                    );
                  }, childCount: shown.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: wide ? 410 : 350,
                    crossAxisSpacing: Space.l,
                    mainAxisSpacing: Space.l + 2,
                  ),
                );
              },
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, Space.xl, gutter, Space.huge + 40),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pages > 1 && _tab != 2)
                  Center(
                    child: Pagination(page: page, pages: pages, onPage: (p) => setState(() => _page = p)),
                  ),
                if (_query.trim().isNotEmpty && _tab != 2) ...[
                  const SizedBox(height: Space.xl),
                  const SectionHeader('Keep exploring'),
                  const SizedBox(height: Space.m),
                  Wrap(
                    spacing: Space.m,
                    runSpacing: Space.s,
                    children: [
                      PaperButton(
                        label: 'Google Shopping',
                        icon: Icons.north_east,
                        compact: true,
                        onPressed: () => _open(Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': _query}).toString()),
                      ),
                      PaperButton(
                        label: 'Etsy',
                        icon: Icons.north_east,
                        compact: true,
                        onPressed: () => _open(Uri.https('www.etsy.com', '/search', {'q': _query}).toString()),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.xl),
                const Text(
                  'Inspiration samples are illustrative, not live offers. Share or import a link to build your real catalog.',
                  style: TextStyle(fontSize: 12, color: Tone.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: gutter,
        title: const Text('vastra.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.4, color: Tone.ink)),
        actions: [
          PaperIconButton(icon: Icons.ios_share, tooltip: 'Export catalog', onPressed: _export),
          const SizedBox(width: Space.s),
          PaperIconButton(icon: Icons.tune, tooltip: 'Settings', onPressed: _settings),
          const SizedBox(width: Space.m),
          CopperButton(label: wide ? 'Add a product link' : 'Add link', icon: Icons.add, compact: true, onPressed: _import),
          SizedBox(width: gutter),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (wide)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FolderTabs(labels: _tabs, selected: _tab, onSelect: _navigate),
                ),
              ),
            if (wide) const Divider(height: 1, thickness: 2, color: Tone.copper),
            Expanded(child: FadeThrough(child: KeyedSubtree(key: ValueKey(_tab), child: body))),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                decoration: paperDecoration(level: 3, radius: Radii.m),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == _tab,
                          button: true,
                          label: _tabs[i],
                          excludeSemantics: true,
                          child: InkResponse(
                            onTap: () {
                              if (i == _tab) return;
                              FeedbackScope.of(context).play(Cue.toggle);
                              _navigate(i);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: Motion.medium,
                                    curve: Motion.ease,
                                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 5),
                                    decoration: i == _tab ? paperDecoration(surface: Surface.inset, radius: Radii.m, border: Tone.copper) : null,
                                    child: Icon(_tabIcons[i], color: i == _tab ? Tone.copper : Tone.inkSoft, size: 22),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    i == 1 ? 'Catalog' : _tabs[i],
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w400,
                                      color: i == _tab ? Tone.copper : Tone.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: AnimatedScale(
        scale: _comparison.isEmpty ? 0 : 1,
        duration: Motion.medium,
        curve: Motion.settle,
        child: CopperButton(
          label: 'Compare ${_comparison.length}',
          icon: Icons.compare_arrows,
          onPressed: _comparison.isEmpty ? null : _compare,
        ),
      ),
    );
  }
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto(this.product, {super.key, this.index = 0});
  final Product product;
  final int index;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
      decoration: paperDecoration(surface: Surface.inset, radius: Radii.none),
      alignment: Alignment.center,
      child: const Icon(Icons.checkroom_outlined, size: 42, color: Tone.copperLight),
    );
    Widget fadeIn(Widget child, int? frame, bool sync) => sync
        ? child
        : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.slow, curve: Motion.ease, child: child);
    if (product.sample) {
      return Image.asset(
        'assets/images/${product.id}.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        frameBuilder: (_, child, frame, sync) => fadeIn(child, frame, sync),
        errorBuilder: (_, error, stack) => fallback(),
      );
    }
    return product.images.length <= index
        ? fallback()
        : Image.network(
            product.images[index],
            fit: BoxFit.cover,
            width: double.infinity,
            frameBuilder: (_, child, frame, sync) => fadeIn(child, frame, sync),
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
  Widget build(BuildContext context) {
    final fresh = !product.sample &&
        (DateTime.tryParse(product.checkedAt)?.isAfter(DateTime.now().subtract(const Duration(days: 7))) ?? false);
    return Pressable(
      onTap: onOpen,
      cue: Cue.open,
      radius: Radii.s,
      padding: const EdgeInsets.all(Space.m - 2),
      semanticLabel: 'View ${product.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs - 1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(tag: 'photo-${product.id}', child: ProductPhoto(product)),
                    Positioned(
                      top: Space.s,
                      left: 0,
                      child: RibbonBadge(
                        product.sample ? 'Sample' : (fresh ? 'New' : (product.extraction == 'link' ? 'Link' : 'Yours')),
                        color: product.sample ? Tone.inkSoft : Tone.copper,
                      ),
                    ),
                    Positioned(
                      top: Space.xs,
                      right: Space.xs,
                      child: PaperIconButton(
                        icon: saved ? Icons.favorite : Icons.favorite_border,
                        tooltip: saved ? 'Unsave ${product.name}' : 'Save ${product.name}',
                        onPressed: onSave,
                        active: saved,
                        cue: Cue.toggle,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s + 2),
          Text(
            product.brand.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: Tone.inkSoft),
          ),
          const SizedBox(height: 2),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: Space.xs),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    product.displayOffer?.priceText ?? 'Price unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Tone.copper, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                // Narrow phone cards keep the price readable and shrink Compare to its icon.
                if (constraints.maxWidth < 240)
                  PaperIconButton(
                    icon: compared ? Icons.check : Icons.add,
                    tooltip: compared ? 'Remove from comparison' : 'Compare',
                    active: compared,
                    cue: Cue.toggle,
                    size: 34,
                    onPressed: onCompare,
                  )
                else
                  PaperButton(
                    label: compared ? 'Added' : 'Compare',
                    icon: compared ? Icons.check : Icons.add,
                    compact: true,
                    selected: compared,
                    cue: Cue.toggle,
                    onPressed: onCompare,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal shelf of small cards.
class SimilarStrip extends StatelessWidget {
  const SimilarStrip({super.key, required this.products, required this.onOpen});
  final List<Product> products;
  final void Function(Product) onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 214,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(width: Space.m),
      itemBuilder: (context, i) {
        final p = products[i];
        return Arrive(
          index: i,
          child: SizedBox(
            width: 150,
            child: Pressable(
              onTap: () => onOpen(p),
              cue: Cue.open,
              padding: const EdgeInsets.all(Space.s),
              semanticLabel: 'View ${p.name}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(borderRadius: BorderRadius.circular(Radii.xs), child: ProductPhoto(p)),
                  ),
                  const SizedBox(height: Space.s),
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(
                    p.displayOffer?.priceText ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Tone.copper, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ProductDetail extends StatefulWidget {
  const _ProductDetail({required this.product, required this.home, required this.close});
  final Product product;
  final _HomeState home;
  final VoidCallback close;
  @override
  State<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<_ProductDetail> {
  late Product _product = widget.product;
  late final _collection = TextEditingController(text: widget.home._saved(_product) ?? 'My edit');
  final _photos = PageController();
  int _photo = 0;

  @override
  void dispose() {
    _collection.dispose();
    _photos.dispose();
    super.dispose();
  }

  Widget _fact(String label, String? value) => value == null || value.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5))),
              const SizedBox(width: Space.l),
              Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5))),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final home = widget.home;
    final p = _product;
    final saved = home._saved(p);
    final similar = home._recommender.similarTo(p);
    final photos = p.sample ? 1 : p.images.length.clamp(1, 12);
    final kind = kindOf(p.category, p.productType);
    return PaperSheet(
      maxWidth: 720,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Breadcrumbs([p.category, ?p.productType, if (p.sourceCategory != null && p.sourceCategory!.length < 40) p.sourceCategory!.split(' > ').last]),
                    ),
                  ),
                  PaperIconButton(icon: Icons.close, tooltip: 'Close product', onPressed: widget.close),
                ],
              ),
              const SizedBox(height: Space.l),
              Container(
                height: 300,
                decoration: paperDecoration(surface: Surface.inset, radius: Radii.s),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.s - 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _photos,
                        itemCount: photos,
                        onPageChanged: (i) => setState(() => _photo = i),
                        itemBuilder: (_, i) => i == 0
                            ? Hero(tag: 'photo-${p.id}', child: ProductPhoto(p))
                            : ProductPhoto(p, index: i),
                      ),
                      if (photos > 1)
                        Positioned(
                          bottom: Space.s,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < photos; i++)
                                AnimatedContainer(
                                  duration: Motion.medium,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _photo ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _photo ? Tone.copper : Tone.paper.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(p.brand.toUpperCase(), style: const TextStyle(fontSize: 11.5, letterSpacing: 1.2, color: Tone.copper)),
              const SizedBox(height: Space.s),
              Text(p.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2)),
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Text(
                    p.displayOffer?.priceText ?? 'Price unavailable',
                    style: const TextStyle(fontSize: 20, color: Tone.copper, fontWeight: FontWeight.w700),
                  ),
                  if (p.rating != null) ...[
                    const SizedBox(width: Space.m),
                    const Icon(Icons.star_rounded, size: 18, color: Tone.copper),
                    Text(' ${p.rating}${p.reviewCount == null ? '' : ' · ${p.reviewCount} reviews'}', style: const TextStyle(fontSize: 12.5)),
                  ],
                ],
              ),
              const SizedBox(height: Space.m),
              Text(
                p.description.isEmpty ? 'No description was provided by the source.' : p.description,
                style: const TextStyle(color: Tone.ink),
              ),
              const SizedBox(height: Space.xl),
              const SectionHeader('Details'),
              const SizedBox(height: Space.s),
              _fact('Material / formulation', p.material ?? 'Not provided by seller'),
              _fact('Colour', p.color),
              _fact('Pattern', p.pattern),
              _fact('Sizes listed', p.sizes.isEmpty ? 'Check with seller' : p.sizes.join(' · ')),
              _fact('For', [?p.gender, ?p.ageGroup].join(' · ')),
              _fact('Condition', p.condition),
              _fact('SKU', p.sku),
              _fact('Barcode (GTIN)', p.gtin),
              _fact('Maker part number', p.mpn),
              _fact('Shipping, taxes and duties', 'Not included — confirm at checkout'),
              _fact('Quality evidence', p.sample ? 'Illustrative sample only' : 'Seller-provided; not independently verified'),
              if (p.variants.isNotEmpty) ...[
                const SizedBox(height: Space.l),
                const SectionHeader('Variants'),
                const SizedBox(height: Space.s),
                Paper(
                  padding: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowMinHeight: 34,
                      dataRowMaxHeight: 40,
                      headingRowColor: const WidgetStatePropertyAll(Tone.paperHigh),
                      headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Tone.ink, fontSize: 12.5),
                      dataTextStyle: const TextStyle(fontSize: 12.5, color: Tone.ink),
                      columns: const [
                        DataColumn(label: Text('Size')),
                        DataColumn(label: Text('Colour')),
                        DataColumn(label: Text('Price')),
                        DataColumn(label: Text('Stock')),
                        DataColumn(label: Text('SKU')),
                      ],
                      rows: [
                        for (final v in p.variants.take(40))
                          DataRow(
                            cells: [
                              DataCell(Text(v.size ?? '—')),
                              DataCell(Text(v.color ?? '—')),
                              DataCell(Text(v.price == null ? '—' : Offer(seller: '', url: '', price: v.price, currency: v.currency).priceText)),
                              DataCell(Text(v.availability ?? '—')),
                              DataCell(Text(v.sku ?? '—')),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Space.l),
              const SectionHeader('Offers'),
              const SizedBox(height: Space.s),
              for (final o in p.offers)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Paper(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.priceText, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${o.seller} · ${o.availability}', style: const TextStyle(fontSize: 12.5, color: Tone.inkSoft)),
                            ],
                          ),
                        ),
                        if (o.url.isNotEmpty) PaperIconButton(icon: Icons.north_east, tooltip: 'View original offer', onPressed: () => home._open(o.url)),
                      ],
                    ),
                  ),
                ),
              Text(
                p.sample
                    ? 'Sample imagery, specifications and pricing are illustrative. This is not a live listing.'
                    : 'Checked ${DateTime.tryParse(p.checkedAt)?.toLocal().toString().split('.').first ?? p.checkedAt}. Price and stock can change. Missing facts remain unknown.',
                style: const TextStyle(fontSize: 12, color: Tone.inkSoft),
              ),
              if (!p.sample) ...[
                const SizedBox(height: Space.xl),
                const SectionHeader('Category'),
                const SizedBox(height: Space.m),
                Text(
                  p.categorySource == 'user'
                      ? 'You chose this category. Vastra learns from it for future finds.'
                      : 'Filed automatically${kind == null ? '' : ' as ${kind.type}'}. Tap to correct it; Vastra learns from your choice.',
                  style: const TextStyle(fontSize: 12.5, color: Tone.inkSoft),
                ),
                const SizedBox(height: Space.m),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final category in home.widget.data.categories.where((c) => c != 'All discoveries'))
                      PaperButton(
                        label: category,
                        compact: true,
                        selected: p.category == category,
                        cue: Cue.toggle,
                        onPressed: () => _recategorize(category, null),
                      ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final k in kinds.where((k) => k.category == p.category).map((k) => k.type).toSet())
                      ChoiceChip(
                        label: Text(k),
                        selected: p.productType == k,
                        onSelected: (_) => _recategorize(p.category, k),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Space.xl),
              const SectionHeader('Keep it'),
              const SizedBox(height: Space.m),
              PaperField(controller: _collection, label: 'Collection name', enabled: saved == null, maxLength: 60),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  CopperButton(
                    label: saved == null ? 'Save to collection' : 'Remove from collection',
                    icon: saved == null ? Icons.favorite_border : Icons.favorite,
                    cue: Cue.toggle,
                    onPressed: () {
                      home._save(p, _collection.text.trim().isEmpty ? 'My edit' : _collection.text.trim());
                      setState(() {});
                    },
                  ),
                  PaperButton(
                    label: home._comparison.contains(p.id) ? 'In comparison' : 'Compare',
                    icon: home._comparison.contains(p.id) ? Icons.check : Icons.add,
                    selected: home._comparison.contains(p.id),
                    cue: Cue.toggle,
                    onPressed: () {
                      home._toggleCompare(p);
                      setState(() {});
                    },
                  ),
                ],
              ),
              if (similar.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                const SectionHeader('More like this'),
                const SizedBox(height: Space.m),
                SimilarStrip(
                  products: similar,
                  onOpen: (s) {
                    widget.close();
                    home._detail(s);
                  },
                ),
              ],
              const SizedBox(height: Space.l),
              Text('Find similar elsewhere: ${Recommender.searchQuery(p)}', style: const TextStyle(fontSize: 12.5, color: Tone.inkSoft)),
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final (label, uri) in [
                    ('Google Shopping', Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': Recommender.searchQuery(p)})),
                    ('Pinterest', Uri.https('www.pinterest.com', '/search/pins/', {'q': Recommender.searchQuery(p)})),
                    ('Etsy', Uri.https('www.etsy.com', '/search', {'q': Recommender.searchQuery(p)})),
                  ])
                    PaperButton(label: label, icon: Icons.north_east, compact: true, onPressed: () => home._open(uri.toString())),
                ],
              ),
              if (!p.sample) ...[
                const Divider(height: Space.xxl + 8),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    PaperButton(label: 'Original product', icon: Icons.open_in_new, compact: true, onPressed: () => home._open(p.sourceUrl)),
                    PaperButton(
                      label: 'Copy link',
                      icon: Icons.copy,
                      compact: true,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: p.sourceUrl));
                        home._dismissedLink = p.sourceUrl;
                        home._toast(ToastKind.info, 'Product link copied.');
                      },
                    ),
                    PaperButton(
                      label: 'Refresh details',
                      icon: Icons.refresh,
                      compact: true,
                      onPressed: () {
                        widget.close();
                        home._import(p.sourceUrl);
                      },
                    ),
                    PaperButton(label: 'Remove', icon: Icons.delete_outline, compact: true, onPressed: () => home._remove(p, context)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _recategorize(String category, String? type) {
    widget.home._recategorize(_product, category, type);
    setState(() => _product = _product.withCategory(category, type));
  }
}

/// Fetches a shared or pasted link, showing each step as it happens.
class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key, required this.importer, required this.repository, this.initial = '', this.auto = false});
  final ProductImporter importer;
  final CatalogRepository repository;
  final String initial;
  final bool auto;
  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  late final TextEditingController _url = TextEditingController(text: widget.initial);
  bool _busy = false;
  int _step = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.auto && widget.initial.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      widget.importer.validate(_url.text);
    } on ImportFailure catch (error) {
      FeedbackScope.of(context).play(Cue.error);
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _step = 1;
    });
    try {
      final product = await widget.importer.fetch(_url.text);
      if (!mounted) return;
      setState(() => _step = 2);
      final stored = widget.repository.importProduct(product);
      setState(() => _step = 3);
      await Future<void>.delayed(Motion.medium);
      if (mounted) Navigator.pop(context, stored);
    } on ImportFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = 'The product could not be saved. Your existing catalog has not been reset.');
    } finally {
      if (mounted) {
        if (_error != null) FeedbackScope.of(context).play(Cue.error);
        setState(() {
          _busy = false;
          if (_error != null) _step = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: PaperSheet(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('A link to your next good find.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.s),
            const Text(
              'Paste or share a product from any store or app. Vastra gathers its details, files it in the right category and keeps it on this device. Importing a link again refreshes it.',
              style: TextStyle(color: Tone.inkSoft),
            ),
            const SizedBox(height: Space.xl),
            StepTrack(steps: const ['Link', 'Fetching', 'Details', 'Saved'], active: _step),
            const SizedBox(height: Space.xl),
            PaperField(
              controller: _url,
              label: 'Product link',
              hint: 'https://store.com/product/…',
              autofocus: !widget.auto,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              maxLength: 4096,
              error: _error,
              helper: 'Shared text is fine too: Vastra finds the link inside.',
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
            ),
            AnimatedSize(
              duration: Motion.medium,
              curve: Motion.ease,
              child: _busy
                  ? Padding(
                      padding: const EdgeInsets.only(top: Space.l),
                      child: Column(
                        children: [
                          CopperProgress(
                            value: _step / 3,
                            label: _step == 1 ? 'Gathering details…' : 'Filing in your catalog…',
                          ),
                          const SizedBox(height: Space.m),
                          const SkeletonRows(),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Space.l),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                iconColor: Tone.copper,
                collapsedIconColor: Tone.copper,
                title: Text('What Vastra reads', style: TextStyle(fontSize: 13)),
                children: [
                  Text(
                    'Names, brand, prices in their original currency, stock, sizes, colours, materials, barcodes, ratings and photos that the store publishes. If a store blocks automated reading, the link is still saved with what it shared, and you can refresh it later. Shipping, taxes, duties, quality and returns must be confirmed with the seller.',
                    style: TextStyle(fontSize: 12, color: Tone.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.l),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.m,
              runSpacing: Space.s,
              children: [
                PaperButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
                CopperButton(label: _busy ? 'Importing' : 'Import product', icon: Icons.add_link, busy: _busy, onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Saves the catalog for another platform.
class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.products, required this.collections, required this.onDone});
  final List<CatalogEntry> products;
  final List<String> collections;
  final void Function(String message, bool ok) onDone;
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportFormat _format = ExportFormat.shopify;
  String _scope = 'Whole catalog';
  bool _busy = false;

  List<Product> get _chosen => [
    for (final e in widget.products)
      if (_scope == 'Whole catalog' || e.collection == _scope) e.product,
  ];

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final text = exportCatalog(_chosen, _format);
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Export Vastra catalog',
        fileName: 'vastra-${_format.name}-$stamp.${_format.extension}',
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: switch (_format) {
          ExportFormat.shopify => 'text/csv',
          ExportFormat.merchantFeed => 'text/tab-separated-values',
          ExportFormat.schemaJson => 'application/json',
        },
      );
      if (saved == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      widget.onDone('Exported ${_chosen.length} products for ${_format.label.split(' (').first}.', true);
      if (mounted) Navigator.pop(context);
    } on Object {
      widget.onDone('The export could not be saved. Try another folder.', false);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PaperSheet(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Take your catalog anywhere.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: Space.s),
          const Text(
            'Every detail Vastra gathered, in formats stores and catalogs import directly. Nothing is uploaded; you choose where the file goes.',
            style: TextStyle(color: Tone.inkSoft),
          ),
          const SizedBox(height: Space.xl),
          if (widget.products.isEmpty)
            const EmptyState(title: 'No Items Found', message: 'Import or share a product first. Samples are not exported.')
          else ...[
            const SectionHeader('Format'),
            RadioGroup<ExportFormat>(
              groupValue: _format,
              onChanged: (v) {
                FeedbackScope.of(context).play(Cue.toggle);
                setState(() => _format = v!);
              },
              child: Column(
                children: [
                  for (final f in ExportFormat.values)
                    RadioListTile<ExportFormat>(
                      value: f,
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.label),
                      subtitle: Text(f.hint, style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.m),
            const SectionHeader('Products'),
            const SizedBox(height: Space.m),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final scope in ['Whole catalog', ...widget.collections])
                  PaperButton(
                    label: scope,
                    compact: true,
                    selected: _scope == scope,
                    cue: Cue.toggle,
                    onPressed: () => setState(() => _scope = scope),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            Text('${_chosen.length} products', style: const TextStyle(fontSize: 12.5, color: Tone.inkSoft)),
          ],
          const SizedBox(height: Space.xl),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.m,
            runSpacing: Space.s,
            children: [
              PaperButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
              CopperButton(
                label: 'Export',
                icon: Icons.download,
                busy: _busy,
                onPressed: _chosen.isEmpty ? null : _save,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
