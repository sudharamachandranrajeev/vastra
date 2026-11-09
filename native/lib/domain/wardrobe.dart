// What the owner keeps in their wardrobe: items they own, what they wore,
// outfits and moodboards, a day-by-day plan and packing lists. All of it
// stays on the device.

/// A day as `2026-11-09`, the key used for wears and plans.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// An item the owner has. [price] is what they paid, in [currency].
class Own {
  const Own({required this.productId, this.price, this.currency = '', this.boughtOn});
  final String productId;
  final double? price;
  final String currency;
  final DateTime? boughtOn;
}

/// A board of catalog items. A moodboard may mix items the owner has with
/// ones they only want; [mood] only changes the label.
class Outfit {
  const Outfit({this.id = 0, required this.name, this.mood = false, this.itemIds = const [], this.note = ''});
  final int id;
  final String name, note;
  final bool mood;
  final List<String> itemIds;
}

class PackItem {
  const PackItem({required this.label, this.productId, this.packed = false});
  final String label;
  final String? productId;
  final bool packed;
  PackItem copyWith({bool? packed}) =>
      PackItem(label: label, productId: productId, packed: packed ?? this.packed);
}

class PackList {
  const PackList({this.id = 0, required this.name, this.items = const []});
  final int id;
  final String name;
  final List<PackItem> items;
}

/// An outfit planned for [day]; [remind] asks for a notification that morning.
class PlanEntry {
  const PlanEntry({required this.day, required this.outfitId, this.remind = false});
  final String day;
  final int outfitId;
  final bool remind;
}

/// Price paid divided by days worn. Null when the price is unknown or the
/// item has not been worn, so nothing is invented.
double? costPerWear(Own? own, int wears) {
  final price = own?.price;
  if (price == null || wears <= 0) return null;
  return price / wears;
}

String money(double amount, String currency) =>
    '${currency.isEmpty ? '' : '$currency '}${amount.toStringAsFixed(2)}';

class WornItem {
  const WornItem({
    required this.productId,
    required this.name,
    required this.own,
    required this.wears,
    this.last,
  });
  final String productId, name;
  final Own own;
  final int wears;
  final String? last;
}

class WardrobeStats {
  const WardrobeStats({
    required this.count,
    required this.spent,
    required this.mostWorn,
    required this.neverWorn,
    required this.bestValue,
  });
  final int count;

  /// Total paid per currency. Currencies are never added together.
  final Map<String, double> spent;
  final List<WornItem> mostWorn, neverWorn;

  /// Items with a price and at least one wear, cheapest per wear first.
  final List<WornItem> bestValue;
}

WardrobeStats wardrobeStats(List<WornItem> items, {int top = 5}) {
  final spent = <String, double>{};
  for (final i in items) {
    final p = i.own.price;
    if (p != null) spent[i.own.currency] = (spent[i.own.currency] ?? 0) + p;
  }
  final worn = items.where((i) => i.wears > 0).toList();
  double per(WornItem i) => costPerWear(i.own, i.wears)!;
  return WardrobeStats(
    count: items.length,
    spent: spent,
    mostWorn: ([...worn]..sort((a, b) => b.wears.compareTo(a.wears))).take(top).toList(),
    neverWorn: items.where((i) => i.wears == 0).toList(),
    bestValue: (worn.where((i) => i.own.price != null).toList()..sort((a, b) => per(a).compareTo(per(b))))
        .take(top)
        .toList(),
  );
}

/// The notification text for the outfits planned today, or null.
({String title, String body})? reminderFor(List<Outfit> planned, Map<String, String> names) {
  if (planned.isEmpty) return null;
  final first = planned.first;
  final items = first.itemIds.map((id) => names[id]).whereType<String>().toList();
  return (
    title: planned.length == 1 ? "Today's outfit: ${first.name}" : '${planned.length} outfits planned today',
    body: planned.length == 1
        ? (items.isEmpty ? 'Open Vastra to see it.' : items.join(', '))
        : planned.map((o) => o.name).join(', '),
  );
}
