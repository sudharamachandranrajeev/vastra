import 'package:intl/intl.dart';

class Offer {
  const Offer({
    required this.seller,
    required this.url,
    this.price,
    this.currency,
    this.availability = 'Unknown',
  });
  final String seller, url, availability;
  final double? price;
  final String? currency;

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
    seller: json['seller'] as String,
    url: json['url'] as String,
    price: (json['price'] as num?)?.toDouble(),
    currency: json['currency'] as String?,
    availability: json['availability'] as String? ?? 'Unknown',
  );
  Map<String, dynamic> toJson() => {
    'seller': seller,
    'url': url,
    'price': price,
    'currency': currency,
    'availability': availability,
  };
  String get priceText => price == null || currency == null
      ? 'Price unavailable'
      : '$currency ${NumberFormat.simpleCurrency(name: currency).format(price)}';
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.description,
    required this.images,
    required this.offers,
    required this.sourceUrl,
    required this.checkedAt,
    required this.sample,
    required this.extraction,
    this.material,
    this.color,
    this.sizes = const [],
  });
  final String id, name, brand, category, description, sourceUrl, checkedAt, extraction;
  final List<String> images, sizes;
  final List<Offer> offers;
  final String? material, color;
  final bool sample;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String,
    category: json['category'] as String,
    description: json['description'] as String,
    sourceUrl: json['sourceUrl'] as String,
    checkedAt: json['checkedAt'] as String,
    extraction: json['extraction'] as String,
    sample: json['sample'] as bool,
    images: List<String>.from(json['images'] as List),
    sizes: List<String>.from(json['sizes'] as List? ?? []),
    offers: (json['offers'] as List).map((e) => Offer.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    material: json['material'] as String?,
    color: json['color'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'category': category,
    'description': description,
    'sourceUrl': sourceUrl,
    'checkedAt': checkedAt,
    'extraction': extraction,
    'sample': sample,
    'images': images,
    'sizes': sizes,
    'offers': offers.map((o) => o.toJson()).toList(),
    'material': material,
    'color': color,
  };
  Product withId(String value) => Product.fromJson({...toJson(), 'id': value});
  Offer? get displayOffer {
    if (offers.isEmpty) return null;
    final priced = offers.where((o) => o.price != null && o.currency != null).toList();
    if (priced.isEmpty || priced.map((o) => o.currency).toSet().length > 1) return offers.first;
    priced.sort((a, b) => a.price!.compareTo(b.price!));
    return priced.first;
  }

  bool matches(String query, String selectedCategory) {
    final haystack = '$name $brand $category $description ${material ?? ''} ${color ?? ''}'.toLowerCase();
    return (selectedCategory == 'All discoveries' || selectedCategory == category) &&
        query.trim().toLowerCase().split(RegExp(r'\s+')).every(haystack.contains);
  }
}
