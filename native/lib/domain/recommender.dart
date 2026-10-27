import 'dart:math' as math;

import 'categorizer.dart';
import 'product.dart';

/// Content-based "more like this", the method behind Lucene's MoreLikeThis
/// and scikit-learn's TfidfVectorizer: each product becomes a TF-IDF vector
/// of its words, and neighbours are ranked by cosine similarity, nudged by
/// shared facets (type, colour, brand, close price). Runs on the device.
class Recommender {
  Recommender(this.products) {
    final documentFrequency = <String, int>{};
    final terms = [for (final p in products) _terms(p)];
    for (final t in terms) {
      for (final word in t.keys) {
        documentFrequency.update(word, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    for (var i = 0; i < products.length; i++) {
      final vector = <String, double>{
        for (final MapEntry(key: word, value: count) in terms[i].entries)
          word: (1 + math.log(count)) * math.log((1 + products.length) / (1 + documentFrequency[word]!)) + 1,
      };
      final norm = math.sqrt(vector.values.fold(0.0, (s, v) => s + v * v));
      _vectors[products[i].id] = norm == 0 ? vector : vector.map((k, v) => MapEntry(k, v / norm));
    }
  }

  final List<Product> products;
  final _vectors = <String, Map<String, double>>{};

  // Names and types say most about what a product is, so they count more.
  static Map<String, int> _terms(Product p) {
    final counts = <String, int>{};
    void add(String text, int weight) {
      for (final t in tokenize(text)) {
        counts.update(t, (v) => v + weight, ifAbsent: () => weight);
      }
    }

    add(p.name, 3);
    add('${p.productType ?? ''} ${p.category}', 3);
    add('${p.color ?? ''} ${p.material ?? ''} ${p.pattern ?? ''}', 2);
    add('${p.brand} ${p.sourceCategory ?? ''} ${p.tags.join(' ')}', 1);
    add(p.description, 1);
    return counts;
  }

  double similarity(Product a, Product b) {
    final va = _vectors[a.id], vb = _vectors[b.id];
    if (va == null || vb == null) return 0;
    var cosine = 0.0;
    for (final MapEntry(key: word, value: weight) in va.entries) {
      cosine += weight * (vb[word] ?? 0);
    }
    var score = cosine;
    if (a.category == b.category) score += 0.1;
    if (a.productType != null && a.productType == b.productType) score += 0.15;
    if (a.color != null && a.color!.toLowerCase() == b.color?.toLowerCase()) score += 0.05;
    if (a.brand == b.brand) score += 0.05;
    final pa = a.displayOffer, pb = b.displayOffer;
    if (pa?.price != null && pb?.price != null && pa!.currency == pb!.currency && pa.price! > 0 && pb.price! > 0) {
      // Within the same price band; halving or doubling costs the whole bonus.
      score += 0.1 * math.max(0, 1 - (math.log(pa.price! / pb.price!) / math.ln2).abs());
    }
    return score;
  }

  /// Up to [limit] products most like [product], best first.
  List<Product> similarTo(Product product, {int limit = 6}) {
    final scored = [
      for (final p in products)
        if (p.id != product.id) (p, similarity(product, p)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.where((s) => s.$2 > 0.12).take(limit).map((s) => s.$1).toList();
  }

  /// Products like the ones in [liked], excluding those already liked.
  List<Product> forYou(Iterable<Product> liked, {int limit = 8}) {
    final likedIds = {for (final p in liked) p.id};
    if (likedIds.isEmpty) return [];
    final scored = [
      for (final p in products)
        if (!likedIds.contains(p.id))
          (p, liked.map((l) => similarity(l, p)).fold(0.0, math.max)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.where((s) => s.$2 > 0.12).take(limit).map((s) => s.$1).toList();
  }

  /// Words to search other stores for products like this one.
  static String searchQuery(Product p) => [
    if (p.color != null) p.color,
    if (p.material != null && p.material!.length < 30) p.material,
    p.productType ?? p.category,
    if (p.gender != null) p.gender,
  ].join(' ');
}
