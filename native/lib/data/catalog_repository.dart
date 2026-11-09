import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/fit.dart';
import '../domain/product.dart';
import '../domain/wardrobe.dart';
import '../domain/watching.dart';

class CatalogEntry {
  const CatalogEntry(this.product, this.collection);
  final Product product;
  final String? collection;
}

class CatalogRepository {
  CatalogRepository(this._db) {
    _db.execute('PRAGMA busy_timeout = 5000');
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version > 1) {
      throw StateError('This catalog needs a newer version of Vastra. Your data has not been changed.');
    }
    if (version == 0) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute(
          'CREATE TABLE products (id TEXT PRIMARY KEY, source TEXT UNIQUE, document TEXT NOT NULL, collection TEXT)',
        );
        _db.execute('PRAGMA user_version = 1');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    // Watching adds tables without touching `products`, so the catalog stays
    // at version 1 and older versions of Vastra still open it after a rollback.
    _db.execute('''CREATE TABLE IF NOT EXISTS price_points (
      product_id TEXT NOT NULL, seller TEXT NOT NULL, variant TEXT NOT NULL, checked_at TEXT NOT NULL,
      ok INTEGER NOT NULL, price REAL, currency TEXT, availability TEXT)''');
    _db.execute('CREATE INDEX IF NOT EXISTS price_points_product ON price_points (product_id, checked_at)');
    _db.execute('''CREATE TABLE IF NOT EXISTS watches (
      product_id TEXT PRIMARY KEY, variant TEXT NOT NULL, price INTEGER NOT NULL, stock INTEGER NOT NULL,
      rule TEXT NOT NULL, value REAL, immediate INTEGER NOT NULL)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS alerts (
      id INTEGER PRIMARY KEY, product_id TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
      immediate INTEGER NOT NULL, created_at TEXT NOT NULL, delivered_at TEXT)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS fits (
      product_id TEXT PRIMARY KEY, brand TEXT NOT NULL, size TEXT NOT NULL, kept INTEGER NOT NULL,
      fit TEXT NOT NULL, note TEXT NOT NULL, item TEXT NOT NULL, recorded_at TEXT NOT NULL)''');
    _db.execute('CREATE TABLE IF NOT EXISTS private_collections (name TEXT PRIMARY KEY)');
    // Wardrobe tables are additive too.
    _db.execute('''CREATE TABLE IF NOT EXISTS owned (
      product_id TEXT PRIMARY KEY, price REAL, currency TEXT NOT NULL, bought_on TEXT)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS wears (
      product_id TEXT NOT NULL, day TEXT NOT NULL, PRIMARY KEY (product_id, day))''');
    _db.execute('''CREATE TABLE IF NOT EXISTS outfits (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, mood INTEGER NOT NULL, note TEXT NOT NULL)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS outfit_items (
      outfit_id INTEGER NOT NULL, product_id TEXT NOT NULL, pos INTEGER NOT NULL,
      PRIMARY KEY (outfit_id, product_id))''');
    _db.execute(
      '''CREATE TABLE IF NOT EXISTS plans (
      day TEXT NOT NULL, outfit_id INTEGER NOT NULL, remind INTEGER NOT NULL, PRIMARY KEY (day, outfit_id))''',
    );
    _db.execute('CREATE TABLE IF NOT EXISTS packs (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    _db.execute('''CREATE TABLE IF NOT EXISTS pack_items (
      pack_id INTEGER NOT NULL, pos INTEGER NOT NULL, label TEXT NOT NULL, product_id TEXT,
      packed INTEGER NOT NULL)''');
  }
  factory CatalogRepository.memory() => CatalogRepository(sqlite3.openInMemory());
  final Database _db;
  List<CatalogEntry> readAll() => _db
      .select('SELECT document, collection FROM products ORDER BY rowid DESC')
      .map(
        (r) => CatalogEntry(
          Product.fromJson(jsonDecode(r['document'] as String) as Map<String, dynamic>),
          r['collection'] as String?,
        ),
      )
      .toList();

  /// Stores an import or refresh, records its prices in the item's history,
  /// and queues any alert the item's watch asks for.
  Product importProduct(Product product, {DateTime? at}) {
    if (product.sample || product.sourceUrl.isEmpty) {
      throw ArgumentError('An imported product needs a source.');
    }
    final now = (at ?? DateTime.now()).toUtc();
    _db.execute('BEGIN IMMEDIATE');
    try {
      final rows = _db.select('SELECT id, document FROM products WHERE source = ?', [product.sourceUrl]);
      var stored = product;
      if (rows.isNotEmpty) {
        final existing = Product.fromJson(
          jsonDecode(rows.first['document'] as String) as Map<String, dynamic>,
        );
        // A refresh the store blocked keeps the details gathered earlier.
        if (product.extraction == 'link' && existing.extraction != 'link') {
          _record([PricePoint(productId: existing.id, seller: '', variant: '', checkedAt: now, ok: false)]);
          _db.execute('COMMIT');
          return existing;
        }
        stored = product.withId(existing.id);
        if (existing.categorySource == 'user') {
          stored = stored.withCategory(existing.category, existing.productType);
        }
      }
      _db.execute(
        'INSERT INTO products (id, source, document) VALUES (?, ?, ?) ON CONFLICT(source) DO UPDATE SET document = excluded.document',
        [stored.id, stored.sourceUrl, jsonEncode(stored.toJson())],
      );
      if (stored.extraction != 'link') {
        final fresh = observe(stored, now);
        final watch = watchFor(stored.id);
        if (watch != null) {
          for (final alert in evaluate(watch, stored.name, history(stored.id), fresh)) {
            _db.execute(
              'INSERT INTO alerts (product_id, title, body, immediate, created_at) VALUES (?, ?, ?, ?, ?)',
              [alert.productId, alert.title, alert.body, alert.immediate ? 1 : 0, now.toIso8601String()],
            );
          }
        }
        _record(fresh);
      }
      _db.execute('COMMIT');
      return stored;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void save(Product product, String collection) {
    final name = collection.trim();
    if (name.isEmpty || name.length > 60) {
      throw ArgumentError('Use a collection name between 1 and 60 characters.');
    }
    _db.execute(
      'INSERT INTO products (id, source, document, collection) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET collection = excluded.collection',
      [product.id, product.sourceUrl.isEmpty ? null : product.sourceUrl, jsonEncode(product.toJson()), name],
    );
  }

  /// Replaces an imported product's details, keeping its collection.
  void update(Product product) => _db.execute('UPDATE products SET document = ? WHERE id = ?', [
    jsonEncode(product.toJson()),
    product.id,
  ]);

  void unsave(Product product) {
    if (product.sample) {
      _db.execute('DELETE FROM products WHERE id = ?', [product.id]);
    } else {
      _db.execute('UPDATE products SET collection = NULL WHERE id = ?', [product.id]);
    }
  }

  void remove(String id) {
    for (final table in [
      'products WHERE id',
      'price_points WHERE product_id',
      'watches WHERE product_id',
      'fits WHERE product_id',
      'alerts WHERE product_id',
      'owned WHERE product_id',
      'wears WHERE product_id',
      'outfit_items WHERE product_id',
    ]) {
      _db.execute('DELETE FROM $table = ?', [id]);
    }
    _db.execute('UPDATE pack_items SET product_id = NULL WHERE product_id = ?', [id]);
  }

  void _record(List<PricePoint> points) {
    for (final p in points) {
      _db.execute(
        'INSERT INTO price_points (product_id, seller, variant, checked_at, ok, price, currency, availability) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          p.productId,
          p.seller,
          p.variant,
          p.checkedAt.toIso8601String(),
          p.ok ? 1 : 0,
          p.price,
          p.currency,
          p.availability,
        ],
      );
    }
  }

  /// Every recorded check of an item, oldest first.
  List<PricePoint> history(String productId) => _db
      .select('SELECT * FROM price_points WHERE product_id = ? ORDER BY checked_at, rowid', [productId])
      .map(
        (r) => PricePoint(
          productId: r['product_id'] as String,
          seller: r['seller'] as String,
          variant: r['variant'] as String,
          checkedAt: DateTime.parse(r['checked_at'] as String),
          ok: r['ok'] == 1,
          price: (r['price'] as num?)?.toDouble(),
          currency: r['currency'] as String?,
          availability: r['availability'] as String?,
        ),
      )
      .toList();

  /// The latest successful check and whether a later one was blocked.
  ({DateTime? lastOk, bool lastFailed}) freshness(String productId) {
    final rows = _db.select(
      'SELECT checked_at, ok FROM price_points WHERE product_id = ? ORDER BY checked_at DESC, rowid DESC',
      [productId],
    );
    final ok = rows.where((r) => r['ok'] == 1).firstOrNull;
    return (
      lastOk: ok == null ? null : DateTime.parse(ok['checked_at'] as String),
      lastFailed: rows.isNotEmpty && rows.first['ok'] == 0,
    );
  }

  /// When an item was last checked, successfully or not.
  DateTime? lastChecked(String productId) {
    final value = _db.select('SELECT MAX(checked_at) AS at FROM price_points WHERE product_id = ?', [
      productId,
    ]).first['at'];
    return value == null ? null : DateTime.parse(value as String);
  }

  /// Every fit the owner recorded, across all brands.
  List<FitRecord> fits() => _db
      .select('SELECT * FROM fits ORDER BY recorded_at')
      .map(
        (r) => FitRecord(
          productId: r['product_id'] as String,
          brand: r['brand'] as String,
          size: r['size'] as String,
          kept: r['kept'] == 1,
          fit: r['fit'] as String,
          note: r['note'] as String,
          item: r['item'] as String,
        ),
      )
      .toList();

  FitRecord? fitFor(String productId) => fits().where((f) => f.productId == productId).firstOrNull;

  void setFit(FitRecord f) => _db.execute(
    'INSERT OR REPLACE INTO fits (product_id, brand, size, kept, fit, note, item, recorded_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      f.productId,
      f.brand,
      f.size,
      f.kept ? 1 : 0,
      f.fit,
      f.note,
      f.item,
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  void clearFit(String productId) => _db.execute('DELETE FROM fits WHERE product_id = ?', [productId]);

  // ---- Privacy ----

  /// Collections the owner locked: their finds are left out of every export
  /// and shared list.
  Set<String> privateCollections() => {
    for (final r in _db.select('SELECT name FROM private_collections')) r['name'] as String,
  };

  void setPrivate(String collection, bool locked) => locked
      ? _db.execute('INSERT OR IGNORE INTO private_collections (name) VALUES (?)', [collection])
      : _db.execute('DELETE FROM private_collections WHERE name = ?', [collection]);

  // ---- Wardrobe ----

  Map<String, Own> owned() => {
    for (final r in _db.select('SELECT * FROM owned'))
      r['product_id'] as String: Own(
        productId: r['product_id'] as String,
        price: (r['price'] as num?)?.toDouble(),
        currency: r['currency'] as String,
        boughtOn: r['bought_on'] == null ? null : DateTime.tryParse(r['bought_on'] as String),
      ),
  };

  void setOwn(Own o) => _db.execute(
    'INSERT OR REPLACE INTO owned (product_id, price, currency, bought_on) VALUES (?, ?, ?, ?)',
    [o.productId, o.price, o.currency, o.boughtOn == null ? null : dayKey(o.boughtOn!)],
  );

  /// Stops counting the item as owned. Its wear days are kept in case it was a slip.
  void unown(String productId) => _db.execute('DELETE FROM owned WHERE product_id = ?', [productId]);

  Map<String, int> wearCounts() => {
    for (final r in _db.select('SELECT product_id, COUNT(*) AS n FROM wears GROUP BY product_id'))
      r['product_id'] as String: r['n'] as int,
  };

  Map<String, String> lastWorn() => {
    for (final r in _db.select('SELECT product_id, MAX(day) AS d FROM wears GROUP BY product_id'))
      r['product_id'] as String: r['d'] as String,
  };

  List<String> wearDays(String productId) => _db
      .select('SELECT day FROM wears WHERE product_id = ? ORDER BY day DESC', [productId])
      .map((r) => r['day'] as String)
      .toList();

  /// Logs a wear for each item on [day]. Wearing the same item twice in a day counts once.
  void logWear(Iterable<String> productIds, String day) {
    for (final id in productIds) {
      _db.execute('INSERT OR IGNORE INTO wears (product_id, day) VALUES (?, ?)', [id, day]);
    }
  }

  void unlogWear(String productId, String day) =>
      _db.execute('DELETE FROM wears WHERE product_id = ? AND day = ?', [productId, day]);

  List<Outfit> outfits() {
    final items = <int, List<String>>{};
    for (final r in _db.select('SELECT outfit_id, product_id FROM outfit_items ORDER BY pos')) {
      (items[r['outfit_id'] as int] ??= []).add(r['product_id'] as String);
    }
    return _db
        .select('SELECT * FROM outfits ORDER BY id DESC')
        .map(
          (r) => Outfit(
            id: r['id'] as int,
            name: r['name'] as String,
            mood: r['mood'] == 1,
            note: r['note'] as String,
            itemIds: items[r['id'] as int] ?? const [],
          ),
        )
        .toList();
  }

  /// Saves an outfit (a new one when its id is 0) and returns its id.
  int saveOutfit(Outfit o) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      var id = o.id;
      if (id == 0) {
        _db.execute('INSERT INTO outfits (name, mood, note) VALUES (?, ?, ?)', [
          o.name,
          o.mood ? 1 : 0,
          o.note,
        ]);
        id = _db.lastInsertRowId;
      } else {
        _db.execute('UPDATE outfits SET name = ?, mood = ?, note = ? WHERE id = ?', [
          o.name,
          o.mood ? 1 : 0,
          o.note,
          id,
        ]);
        _db.execute('DELETE FROM outfit_items WHERE outfit_id = ?', [id]);
      }
      for (final (pos, item) in o.itemIds.toSet().indexed) {
        _db.execute('INSERT INTO outfit_items (outfit_id, product_id, pos) VALUES (?, ?, ?)', [
          id,
          item,
          pos,
        ]);
      }
      _db.execute('COMMIT');
      return id;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteOutfit(int id) {
    for (final table in ['outfits WHERE id', 'outfit_items WHERE outfit_id', 'plans WHERE outfit_id']) {
      _db.execute('DELETE FROM $table = ?', [id]);
    }
  }

  List<PlanEntry> plans() => _db
      .select('SELECT * FROM plans ORDER BY day')
      .map(
        (r) => PlanEntry(day: r['day'] as String, outfitId: r['outfit_id'] as int, remind: r['remind'] == 1),
      )
      .toList();

  void plan(String day, int outfitId, {bool remind = false}) => _db.execute(
    'INSERT OR REPLACE INTO plans (day, outfit_id, remind) VALUES (?, ?, ?)',
    [day, outfitId, remind ? 1 : 0],
  );

  void unplan(String day, int outfitId) =>
      _db.execute('DELETE FROM plans WHERE day = ? AND outfit_id = ?', [day, outfitId]);

  /// Moves a planned outfit to another day, keeping its reminder choice.
  void movePlan(String from, String to, int outfitId) {
    final entry = plans().where((p) => p.day == from && p.outfitId == outfitId).firstOrNull;
    if (entry == null) return;
    unplan(from, outfitId);
    plan(to, outfitId, remind: entry.remind);
  }

  List<PackList> packLists() {
    final items = <int, List<PackItem>>{};
    for (final r in _db.select('SELECT * FROM pack_items ORDER BY pos')) {
      (items[r['pack_id'] as int] ??= []).add(
        PackItem(
          label: r['label'] as String,
          productId: r['product_id'] as String?,
          packed: r['packed'] == 1,
        ),
      );
    }
    return _db
        .select('SELECT * FROM packs ORDER BY id DESC')
        .map(
          (r) => PackList(
            id: r['id'] as int,
            name: r['name'] as String,
            items: items[r['id'] as int] ?? const [],
          ),
        )
        .toList();
  }

  int savePackList(PackList p) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      var id = p.id;
      if (id == 0) {
        _db.execute('INSERT INTO packs (name) VALUES (?)', [p.name]);
        id = _db.lastInsertRowId;
      } else {
        _db.execute('UPDATE packs SET name = ? WHERE id = ?', [p.name, id]);
        _db.execute('DELETE FROM pack_items WHERE pack_id = ?', [id]);
      }
      for (final (pos, i) in p.items.indexed) {
        _db.execute(
          'INSERT INTO pack_items (pack_id, pos, label, product_id, packed) VALUES (?, ?, ?, ?, ?)',
          [id, pos, i.label, i.productId, i.packed ? 1 : 0],
        );
      }
      _db.execute('COMMIT');
      return id;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deletePackList(int id) {
    _db.execute('DELETE FROM packs WHERE id = ?', [id]);
    _db.execute('DELETE FROM pack_items WHERE pack_id = ?', [id]);
  }

  Watch? watchFor(String productId) =>
      _db.select('SELECT * FROM watches WHERE product_id = ?', [productId]).map(_watch).firstOrNull;

  List<Watch> watches() => _db.select('SELECT * FROM watches').map(_watch).toList();

  Watch _watch(Row r) => Watch(
    productId: r['product_id'] as String,
    variant: r['variant'] as String,
    price: r['price'] == 1,
    stock: r['stock'] == 1,
    rule: PriceRule.values.byName(r['rule'] as String),
    value: (r['value'] as num?)?.toDouble(),
    immediate: r['immediate'] == 1,
  );

  void setWatch(Watch w) => _db.execute(
    'INSERT OR REPLACE INTO watches (product_id, variant, price, stock, rule, value, immediate) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [w.productId, w.variant, w.price ? 1 : 0, w.stock ? 1 : 0, w.rule.name, w.value, w.immediate ? 1 : 0],
  );

  /// Stops watching an item and drops its alerts that were not sent yet.
  void unwatch(String productId) {
    _db.execute('DELETE FROM watches WHERE product_id = ?', [productId]);
    _db.execute('DELETE FROM alerts WHERE product_id = ? AND delivered_at IS NULL', [productId]);
  }

  /// Alerts not yet shown, oldest first, as (id, alert).
  List<(int, WatchAlert)> pendingAlerts() => _db
      .select('SELECT * FROM alerts WHERE delivered_at IS NULL ORDER BY id')
      .map(
        (r) => (
          r['id'] as int,
          WatchAlert(
            productId: r['product_id'] as String,
            title: r['title'] as String,
            body: r['body'] as String,
            immediate: r['immediate'] == 1,
          ),
        ),
      )
      .toList();

  void markDelivered(Iterable<int> ids, DateTime at) {
    for (final id in ids) {
      _db.execute('UPDATE alerts SET delivered_at = ? WHERE id = ?', [at.toUtc().toIso8601String(), id]);
    }
  }

  /// Writes a consistent copy of the whole catalog to [path], which must not
  /// exist yet. The copy is an ordinary Vastra database.
  void backupTo(String path) => _db.execute('VACUUM INTO ?', [path]);

  /// Adds the finds in the backup at [path] that this catalog lacks. Finds
  /// already here are kept as they are, so a restore never loses data.
  /// Returns how many finds were added.
  int restoreFrom(String path) {
    final backup = sqlite3.open(path, mode: OpenMode.readOnly);
    final List<Row> rows, points, watched, fitted, ownedRows, wearRows, locked;
    final backupWardrobe = <String, List<Row>>{};
    try {
      final version = backup.select('PRAGMA user_version').first.values.first as int;
      if (version > 1) {
        throw const FormatException(
          'This backup was made by a newer version of Vastra. Update Vastra, then restore it.',
        );
      }
      final hasTable = backup
          .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'products'")
          .isNotEmpty;
      if (version != 1 || !hasTable) throw const FormatException('This file is not a Vastra catalog backup.');
      rows = backup.select('SELECT id, source, document, collection FROM products').toList();
      bool has(String table) =>
          backup.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table]).isNotEmpty;
      points = has('price_points') ? backup.select('SELECT * FROM price_points').toList() : const [];
      watched = has('watches') ? backup.select('SELECT * FROM watches').toList() : const [];
      fitted = has('fits') ? backup.select('SELECT * FROM fits').toList() : const [];
      ownedRows = has('owned') ? backup.select('SELECT * FROM owned').toList() : const [];
      wearRows = has('wears') ? backup.select('SELECT * FROM wears').toList() : const [];
      locked = has('private_collections')
          ? backup.select('SELECT name FROM private_collections').toList()
          : const [];
      for (final t in ['outfits', 'outfit_items', 'plans', 'packs', 'pack_items']) {
        backupWardrobe[t] = has(t) ? backup.select('SELECT * FROM $t').toList() : const [];
      }
    } on SqliteException {
      throw const FormatException('This file is not a Vastra catalog backup.');
    } finally {
      backup.close();
    }
    var added = 0;
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final r in rows) {
        try {
          // Rows that are not valid products are skipped rather than restored.
          Product.fromJson(jsonDecode(r['document'] as String) as Map<String, dynamic>);
        } on Object {
          continue;
        }
        _db.execute('INSERT OR IGNORE INTO products (id, source, document, collection) VALUES (?, ?, ?, ?)', [
          r['id'],
          r['source'],
          r['document'],
          r['collection'],
        ]);
        if (_db.updatedRows == 0) continue;
        added++;
        // History and watches come along only with finds that are new here.
        for (final p in points.where((p) => p['product_id'] == r['id'])) {
          _db.execute(
            'INSERT INTO price_points (product_id, seller, variant, checked_at, ok, price, currency, availability) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              p['product_id'],
              p['seller'],
              p['variant'],
              p['checked_at'],
              p['ok'],
              p['price'],
              p['currency'],
              p['availability'],
            ],
          );
        }
        for (final f in fitted.where((f) => f['product_id'] == r['id'])) {
          _db.execute(
            'INSERT OR IGNORE INTO fits (product_id, brand, size, kept, fit, note, item, recorded_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              f['product_id'],
              f['brand'],
              f['size'],
              f['kept'],
              f['fit'],
              f['note'],
              f['item'],
              f['recorded_at'],
            ],
          );
        }
        for (final o in ownedRows.where((o) => o['product_id'] == r['id'])) {
          _db.execute(
            'INSERT OR IGNORE INTO owned (product_id, price, currency, bought_on) VALUES (?, ?, ?, ?)',
            [o['product_id'], o['price'], o['currency'], o['bought_on']],
          );
        }
        for (final w in wearRows.where((w) => w['product_id'] == r['id'])) {
          _db.execute('INSERT OR IGNORE INTO wears (product_id, day) VALUES (?, ?)', [
            w['product_id'],
            w['day'],
          ]);
        }
        for (final w in watched.where((w) => w['product_id'] == r['id'])) {
          _db.execute(
            'INSERT OR IGNORE INTO watches (product_id, variant, price, stock, rule, value, immediate) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [w['product_id'], w['variant'], w['price'], w['stock'], w['rule'], w['value'], w['immediate']],
          );
        }
      }
      for (final l in locked) {
        _db.execute('INSERT OR IGNORE INTO private_collections (name) VALUES (?)', [l['name']]);
      }
      _restoreBoards(backupWardrobe);
      _db.execute('COMMIT');
      return added;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Outfits and packing lists come back by name: one already here under the
  /// same name is left alone. Items that are not in this catalog are dropped.
  void _restoreBoards(Map<String, List<Row>> b) {
    final have = {for (final r in _db.select('SELECT id FROM products')) r['id'] as String};
    final outfitNames = {for (final r in _db.select('SELECT name FROM outfits')) r['name'] as String};
    final newOutfit = <int, int>{};
    for (final o in b['outfits']!) {
      if (outfitNames.contains(o['name'])) continue;
      _db.execute('INSERT INTO outfits (name, mood, note) VALUES (?, ?, ?)', [
        o['name'],
        o['mood'],
        o['note'],
      ]);
      newOutfit[o['id'] as int] = _db.lastInsertRowId;
      for (final i in b['outfit_items']!.where(
        (i) => i['outfit_id'] == o['id'] && have.contains(i['product_id']),
      )) {
        _db.execute('INSERT OR IGNORE INTO outfit_items (outfit_id, product_id, pos) VALUES (?, ?, ?)', [
          newOutfit[o['id']],
          i['product_id'],
          i['pos'],
        ]);
      }
    }
    for (final p in b['plans']!.where((p) => newOutfit.containsKey(p['outfit_id']))) {
      _db.execute('INSERT OR IGNORE INTO plans (day, outfit_id, remind) VALUES (?, ?, ?)', [
        p['day'],
        newOutfit[p['outfit_id']],
        p['remind'],
      ]);
    }
    final packNames = {for (final r in _db.select('SELECT name FROM packs')) r['name'] as String};
    for (final p in b['packs']!) {
      if (packNames.contains(p['name'])) continue;
      _db.execute('INSERT INTO packs (name) VALUES (?)', [p['name']]);
      final id = _db.lastInsertRowId;
      for (final i in b['pack_items']!.where((i) => i['pack_id'] == p['id'])) {
        _db.execute(
          'INSERT INTO pack_items (pack_id, pos, label, product_id, packed) VALUES (?, ?, ?, ?, ?)',
          [id, i['pos'], i['label'], have.contains(i['product_id']) ? i['product_id'] : null, i['packed']],
        );
      }
    }
  }

  void close() => _db.close();
}
