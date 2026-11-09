import 'package:intl/intl.dart';

import 'product.dart';

/// One observation of an offer, or of one variant, made by an import or a
/// refresh. A check the store blocked is kept too ([ok] false), so Vastra can
/// tell an old price from a current one.
class PricePoint {
  const PricePoint({
    required this.productId,
    required this.seller,
    required this.variant,
    required this.checkedAt,
    required this.ok,
    this.price,
    this.currency,
    this.availability,
  });
  final String productId, seller, variant;
  final DateTime checkedAt;
  final bool ok;
  final double? price;
  final String? currency, availability;

  String get priceText => price == null || currency == null
      ? 'no price'
      : NumberFormat.simpleCurrency(name: currency).format(price);
}

/// Identifies a variant across refreshes: its size and colour when the store
/// names them, otherwise its SKU or barcode. The empty key means the product
/// as a whole.
String variantKey(Variant v) {
  final named = [v.size, v.color].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ');
  return named.isNotEmpty ? named : (v.sku ?? v.gtin ?? '');
}

/// The points a successful check of [product] yields: one per offer for the
/// whole product, and one per identifiable variant.
List<PricePoint> observe(Product product, DateTime at) {
  final seller = product.offers.firstOrNull?.seller ?? Uri.tryParse(product.sourceUrl)?.host ?? '';
  return [
    for (final o in product.offers)
      PricePoint(
        productId: product.id,
        seller: o.seller,
        variant: '',
        checkedAt: at,
        ok: true,
        price: o.price,
        currency: o.currency,
        availability: o.availability,
      ),
    for (final v in product.variants)
      if (variantKey(v).isNotEmpty)
        PricePoint(
          productId: product.id,
          seller: seller,
          variant: variantKey(v),
          checkedAt: at,
          ok: true,
          price: v.price ?? product.offers.firstOrNull?.price,
          currency: v.currency ?? product.offers.firstOrNull?.currency,
          availability: v.availability,
        ),
  ];
}

/// schema.org availability values that mean the item can be bought now.
bool available(String? availability) =>
    const {'InStock', 'LimitedAvailability', 'OnlineOnly', 'InStoreOnly'}.contains(availability);

/// schema.org availability values that mean it cannot.
bool soldOut(String? availability) => const {'OutOfStock', 'SoldOut', 'Discontinued'}.contains(availability);

enum PriceRule { anyDrop, percent, target }

/// What the owner asked Vastra to watch on one item.
class Watch {
  const Watch({
    required this.productId,
    this.variant = '',
    this.price = true,
    this.stock = true,
    this.rule = PriceRule.anyDrop,
    this.value,
    this.immediate = false,
  });
  final String productId;

  /// A [variantKey], or empty for the whole product.
  final String variant;
  final bool price, stock;
  final PriceRule rule;

  /// The percentage for [PriceRule.percent] or the price for [PriceRule.target].
  final double? value;

  /// Notify as soon as a check finds the change, instead of in the daily digest.
  final bool immediate;

  Watch copyWith({
    String? variant,
    bool? price,
    bool? stock,
    PriceRule? rule,
    double? value,
    bool? immediate,
  }) => Watch(
    productId: productId,
    variant: variant ?? this.variant,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    rule: rule ?? this.rule,
    value: value ?? this.value,
    immediate: immediate ?? this.immediate,
  );
}

class WatchAlert {
  const WatchAlert({
    required this.productId,
    required this.title,
    required this.body,
    required this.immediate,
  });
  final String productId, title, body;
  final bool immediate;
}

/// Compares a fresh, successful check with the last successful one and
/// returns what the owner asked to hear about. Nothing is alerted from a
/// blocked check, from a price in another currency, or for a price drop on
/// something the store says is sold out.
List<WatchAlert> evaluate(Watch watch, String productName, List<PricePoint> before, List<PricePoint> now) {
  final alerts = <WatchAlert>[];
  for (final fresh in now.where((p) => p.ok && p.variant == watch.variant)) {
    final old = before
        .where((p) => p.ok && p.variant == fresh.variant && p.seller == fresh.seller)
        .fold<PricePoint?>(null, (a, p) => a == null || p.checkedAt.isAfter(a.checkedAt) ? p : a);
    if (old == null) continue;
    final where = '${fresh.seller}${fresh.variant.isEmpty ? '' : ', ${fresh.variant}'}';
    final checked = DateFormat('d MMM, HH:mm').format(fresh.checkedAt.toLocal());
    if (watch.stock && available(fresh.availability) && soldOut(old.availability)) {
      alerts.add(
        WatchAlert(
          productId: watch.productId,
          title: 'Back in stock: $productName',
          body:
              '$where has it again${fresh.price == null ? '' : ' at ${fresh.priceText}'}. Checked $checked.',
          immediate: watch.immediate,
        ),
      );
    }
    if (watch.price && _dropped(watch, old, fresh) && !soldOut(fresh.availability)) {
      alerts.add(
        WatchAlert(
          productId: watch.productId,
          title: 'Price drop: $productName',
          body: 'Was ${old.priceText}, now ${fresh.priceText} at $where. Checked $checked.',
          immediate: watch.immediate,
        ),
      );
    }
  }
  return alerts;
}

bool _dropped(Watch watch, PricePoint old, PricePoint fresh) {
  final (a, b) = (old.price, fresh.price);
  if (a == null || b == null || old.currency != fresh.currency || b >= a) return false;
  return switch (watch.rule) {
    PriceRule.anyDrop => true,
    PriceRule.percent => (a - b) / a * 100 >= (watch.value ?? 0) - 1e-9,
    PriceRule.target => watch.value != null && b <= watch.value! && a > watch.value!,
  };
}

/// How long a successful check stays current before Vastra warns about it.
const staleAfter = Duration(days: 7);

/// Why an item's prices may be out of date, or null when they are current.
String? staleReason({required DateTime? lastOk, required bool lastFailed, required DateTime now}) {
  if (lastFailed) return 'The store blocked the last check. Prices may be out of date.';
  if (lastOk == null) return null;
  final age = now.difference(lastOk);
  if (age < staleAfter) return null;
  return 'Last checked ${age.inDays} days ago. Prices may have changed.';
}

/// "checked today", "checked 3 days ago".
String checkedAgo(DateTime at, DateTime now) {
  final days = now.difference(at).inDays;
  return switch (days) {
    <= 0 => 'checked today',
    1 => 'checked yesterday',
    _ => 'checked $days days ago',
  };
}
