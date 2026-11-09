/// What the owner recorded after buying an item: the size, whether they
/// kept it, and how it fit. It never leaves the device.
class FitRecord {
  const FitRecord({
    required this.productId,
    required this.brand,
    required this.size,
    required this.kept,
    required this.fit,
    this.note = '',
    this.item = '',
  });
  final String productId, brand, size, note;

  /// The item's name, for explaining suggestions.
  final String item;
  final bool kept;

  /// 'small', 'right' or 'large'.
  final String fit;

  String get summary =>
      '$item: $size, ${kept ? 'kept' : 'returned'}, ${switch (fit) {
        'small' => 'ran small',
        'large' => 'ran large',
        _ => 'fit right',
      }}';
}

/// Brands compare without case, punctuation or a trailing "Inc."-style word.
String brandKey(String brand) => brand
    .toLowerCase()
    .replaceAll(RegExp(r'\b(inc|ltd|llc|gmbh|co)\b\.?'), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '');

class SizeSuggestion {
  const SizeSuggestion(this.size, this.reason, this.evidence);
  final String size, reason;
  final List<String> evidence;
}

/// The size the owner's own history points to for [brand], with the records
/// behind it. A size kept and fitting right counts most; one kept but tight
/// or loose counts less; a return counts against that size. Nothing is
/// suggested without a size that comes out ahead.
SizeSuggestion? suggestSize(String brand, List<FitRecord> records, {String? excludeProduct}) {
  final key = brandKey(brand);
  if (key.isEmpty) return null;
  final mine = records.where((r) => brandKey(r.brand) == key && r.productId != excludeProduct).toList();
  if (mine.isEmpty) return null;
  final score = <String, int>{};
  for (final r in mine) {
    score[r.size] = (score[r.size] ?? 0) + (!r.kept ? -1 : (r.fit == 'right' ? 2 : 1));
  }
  final best = score.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  if (best.isEmpty) return null;
  final size = best.first.key;
  final at = mine.where((r) => r.size == size && r.kept).toList();
  final small = at.where((r) => r.fit == 'small').length, large = at.where((r) => r.fit == 'large').length;
  final right = at.length - small - large;
  final reason = [
    'You kept ${at.length == 1 ? 'one' : at.length} $brand ${at.length == 1 ? 'item' : 'items'} in $size',
    if (right > 0) '$right fit right',
    if (small > 0) '$small ran small',
    if (large > 0) '$large ran large',
  ].join(', ');
  return SizeSuggestion(size, '$reason.', [for (final r in mine) r.summary]);
}
