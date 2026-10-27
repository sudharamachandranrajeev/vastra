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

/// One purchasable option of a product, as the seller described it.
class Variant {
  const Variant({
    this.sku,
    this.gtin,
    this.size,
    this.color,
    this.price,
    this.currency,
    this.availability,
    this.image,
  });
  final String? sku, gtin, size, color, currency, availability, image;
  final double? price;

  factory Variant.fromJson(Map<String, dynamic> json) => Variant(
    sku: json['sku'] as String?,
    gtin: json['gtin'] as String?,
    size: json['size'] as String?,
    color: json['color'] as String?,
    price: (json['price'] as num?)?.toDouble(),
    currency: json['currency'] as String?,
    availability: json['availability'] as String?,
    image: json['image'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'sku': sku,
    'gtin': gtin,
    'size': size,
    'color': color,
    'price': price,
    'currency': currency,
    'availability': availability,
    'image': image,
  };
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
    this.productType,
    this.categorySource = 'auto',
    this.sourceCategory,
    this.sku,
    this.gtin,
    this.mpn,
    this.gender,
    this.ageGroup,
    this.pattern,
    this.condition,
    this.rating,
    this.reviewCount,
    this.tags = const [],
    this.variants = const [],
  });
  final String id, name, brand, category, description, sourceUrl, checkedAt, extraction;
  final List<String> images, sizes, tags;
  final List<Offer> offers;
  final List<Variant> variants;
  final String? material, color;

  /// Finer type within [category], such as Dresses or Serum.
  final String? productType;

  /// 'user' once someone has corrected the category; refreshes keep it.
  final String categorySource;

  /// The seller's own category or breadcrumb trail, kept verbatim.
  final String? sourceCategory;
  final String? sku, gtin, mpn, gender, ageGroup, pattern, condition;
  final double? rating;
  final int? reviewCount;
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
    productType: json['productType'] as String?,
    categorySource: json['categorySource'] as String? ?? 'auto',
    sourceCategory: json['sourceCategory'] as String?,
    sku: json['sku'] as String?,
    gtin: json['gtin'] as String?,
    mpn: json['mpn'] as String?,
    gender: json['gender'] as String?,
    ageGroup: json['ageGroup'] as String?,
    pattern: json['pattern'] as String?,
    condition: json['condition'] as String?,
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: (json['reviewCount'] as num?)?.toInt(),
    tags: List<String>.from(json['tags'] as List? ?? []),
    variants: (json['variants'] as List? ?? [])
        .map((e) => Variant.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
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
    'productType': productType,
    'categorySource': categorySource,
    'sourceCategory': sourceCategory,
    'sku': sku,
    'gtin': gtin,
    'mpn': mpn,
    'gender': gender,
    'ageGroup': ageGroup,
    'pattern': pattern,
    'condition': condition,
    'rating': rating,
    'reviewCount': reviewCount,
    'tags': tags,
    'variants': variants.map((v) => v.toJson()).toList(),
  };
  Product withId(String value) => Product.fromJson({...toJson(), 'id': value});
  Product withCategory(String value, String? type) =>
      Product.fromJson({...toJson(), 'category': value, 'productType': type, 'categorySource': 'user'});
  Offer? get displayOffer {
    if (offers.isEmpty) return null;
    final priced = offers.where((o) => o.price != null && o.currency != null).toList();
    if (priced.isEmpty || priced.map((o) => o.currency).toSet().length > 1) return offers.first;
    priced.sort((a, b) => a.price!.compareTo(b.price!));
    return priced.first;
  }

  /// Everything a person might search or a model might learn from.
  String get text =>
      '$name $brand $category ${productType ?? ''} ${sourceCategory ?? ''} ${color ?? ''} ${material ?? ''} '
      '${pattern ?? ''} ${gender ?? ''} ${tags.join(' ')} $description';

  bool matches(String query, String selectedCategory) {
    final haystack = text.toLowerCase();
    return (selectedCategory == 'All discoveries' || selectedCategory == category) &&
        query.trim().toLowerCase().split(RegExp(r'\s+')).every(haystack.contains);
  }
}
