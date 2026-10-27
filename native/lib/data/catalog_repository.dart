import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/product.dart';

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

  Product importProduct(Product product) {
    if (product.sample || product.sourceUrl.isEmpty) {
      throw ArgumentError('An imported product needs a source.');
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      final rows = _db.select('SELECT id, document FROM products WHERE source = ?', [product.sourceUrl]);
      var stored = product;
      if (rows.isNotEmpty) {
        final existing = Product.fromJson(jsonDecode(rows.first['document'] as String) as Map<String, dynamic>);
        // A refresh the store blocked keeps the details gathered earlier.
        if (product.extraction == 'link' && existing.extraction != 'link') {
          _db.execute('COMMIT');
          return existing;
        }
        stored = product.withId(existing.id);
        if (existing.categorySource == 'user') stored = stored.withCategory(existing.category, existing.productType);
      }
      _db.execute(
        'INSERT INTO products (id, source, document) VALUES (?, ?, ?) ON CONFLICT(source) DO UPDATE SET document = excluded.document',
        [stored.id, stored.sourceUrl, jsonEncode(stored.toJson())],
      );
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
  void update(Product product) =>
      _db.execute('UPDATE products SET document = ? WHERE id = ?', [jsonEncode(product.toJson()), product.id]);

  void unsave(Product product) {
    if (product.sample) {
      _db.execute('DELETE FROM products WHERE id = ?', [product.id]);
    } else {
      _db.execute('UPDATE products SET collection = NULL WHERE id = ?', [product.id]);
    }
  }

  void remove(String id) => _db.execute('DELETE FROM products WHERE id = ?', [id]);

  /// Writes a consistent copy of the whole catalog to [path], which must not
  /// exist yet. The copy is an ordinary Vastra database.
  void backupTo(String path) => _db.execute('VACUUM INTO ?', [path]);

  /// Adds the finds in the backup at [path] that this catalog lacks. Finds
  /// already here are kept as they are, so a restore never loses data.
  /// Returns how many finds were added.
  int restoreFrom(String path) {
    final backup = sqlite3.open(path, mode: OpenMode.readOnly);
    final List<Row> rows;
    try {
      final version = backup.select('PRAGMA user_version').first.values.first as int;
      if (version > 1) {
        throw const FormatException('This backup was made by a newer version of Vastra. Update Vastra, then restore it.');
      }
      final hasTable = backup.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'products'").isNotEmpty;
      if (version != 1 || !hasTable) throw const FormatException('This file is not a Vastra catalog backup.');
      rows = backup.select('SELECT id, source, document, collection FROM products').toList();
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
        _db.execute(
          'INSERT OR IGNORE INTO products (id, source, document, collection) VALUES (?, ?, ?, ?)',
          [r['id'], r['source'], r['document'], r['collection']],
        );
        added += _db.updatedRows;
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
