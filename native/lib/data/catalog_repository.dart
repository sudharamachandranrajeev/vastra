import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/fit.dart';
import '../domain/product.dart';
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
    ]) {
      _db.execute('DELETE FROM $table = ?', [id]);
    }
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
    final List<Row> rows, points, watched, fitted;
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
        for (final w in watched.where((w) => w['product_id'] == r['id'])) {
          _db.execute(
            'INSERT OR IGNORE INTO watches (product_id, variant, price, stock, rule, value, immediate) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [w['product_id'], w['variant'], w['price'], w['stock'], w['rule'], w['value'], w['immediate']],
          );
        }
      }
      _db.execute('COMMIT');
      return added;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();
}
