import 'dart:convert';

import 'categorizer.dart';
import 'product.dart';

enum ExportFormat {
  shopify('Shopify products CSV', 'csv', 'Import in Shopify admin: Products > Import.'),
  merchantFeed(
    'Product feed (Google, Meta, Pinterest, TikTok)',
    'tsv',
    'Upload as a catalog data feed. Uses the shared Google product data attributes.',
  ),
  schemaJson(
    'Structured JSON (schema.org)',
    'json',
    'Every detail Vastra holds, as schema.org Product data for WooCommerce, BigCommerce or your own tools.',
  );

  const ExportFormat(this.label, this.extension, this.hint);
  final String label, extension, hint;
}

String exportCatalog(List<Product> products, ExportFormat format) => switch (format) {
  ExportFormat.shopify => shopifyCsv(products),
  ExportFormat.merchantFeed => merchantFeed(products),
  ExportFormat.schemaJson => const JsonEncoder.withIndent('  ').convert(schemaOrg(products)),
};

String _csv(List<List<String>> rows) => rows
    .map(
      (row) => row
          .map((cell) => RegExp(r'[",\r\n]').hasMatch(cell) ? '"${cell.replaceAll('"', '""')}"' : cell)
          .join(','),
    )
    .join('\r\n');

String _escape(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _money(double? value) => value == null ? '' : value.toStringAsFixed(2);

String handle(Product p) {
  final slug = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  final suffix = p.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  return '${slug.length > 60 ? slug.substring(0, 60) : slug}-${suffix.substring(0, suffix.length.clamp(0, 6))}';
}

const shopifyColumns = [
  'Handle', 'Title', 'Body (HTML)', 'Vendor', 'Product Category', 'Type', 'Tags', 'Published', //
  'Option1 Name', 'Option1 Value', 'Option2 Name', 'Option2 Value', 'Variant SKU', 'Variant Grams',
  'Variant Inventory Tracker', 'Variant Inventory Qty', 'Variant Inventory Policy', 'Variant Fulfillment Service',
  'Variant Price', 'Variant Compare At Price', 'Variant Requires Shipping', 'Variant Taxable', 'Variant Barcode',
  'Image Src', 'Image Position', 'Image Alt Text', 'Gift Card', 'SEO Title', 'SEO Description', 'Variant Image',
  'Variant Weight Unit', 'Status',
];

/// Shopify's product CSV: one row per variant, then one row per extra image.
/// Products arrive as drafts, because they describe other sellers' goods
/// until you confirm you sell them. Shopify stores one currency, so prices
/// are copied as listed; check them if your store uses another currency.
/// Product Category is left for Shopify to suggest from its own taxonomy.
String shopifyCsv(List<Product> products) {
  final rows = <List<String>>[shopifyColumns];
  for (final p in products) {
    final h = handle(p);
    final variants = p.variants.isEmpty
        ? [Variant(sku: p.sku, gtin: p.gtin, price: p.displayOffer?.price, color: p.color)]
        : p.variants;
    final hasSize = variants.any((v) => v.size != null);
    final hasColor = variants.any((v) => v.color != null) && (p.variants.isNotEmpty || hasSize);
    final option1 = hasSize ? 'Size' : hasColor ? 'Color' : 'Title';
    final option2 = hasSize && hasColor ? 'Color' : '';
    final tags = {
      p.category,
      ?p.productType,
      ...p.tags,
      if (p.gender != null) p.gender!,
    }.map((t) => t.replaceAll(',', ' ')).join(', ');
    final body = [
      if (p.description.isNotEmpty) '<p>${_escape(p.description)}</p>',
      if (p.material != null) '<p>Material: ${_escape(p.material!)}</p>',
    ].join();
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final first = i == 0;
      final image = first ? p.images.firstOrNull : null;
      rows.add([
        h,
        first ? p.name : '',
        first ? body : '',
        first ? p.brand : '',
        '',
        first ? (p.productType ?? p.category) : '',
        first ? tags : '',
        first ? 'FALSE' : '',
        first ? option1 : '',
        option1 == 'Size' ? (v.size ?? '') : option1 == 'Color' ? (v.color ?? '') : 'Default Title',
        first ? option2 : '',
        option2.isEmpty ? '' : (v.color ?? ''),
        v.sku ?? '',
        '',
        '',
        '',
        'deny',
        'manual',
        _money(v.price ?? p.displayOffer?.price),
        '',
        'TRUE',
        'TRUE',
        v.gtin ?? '',
        image ?? '',
        image == null ? '' : '1',
        image == null ? '' : p.name,
        first ? 'FALSE' : '',
        first ? p.name : '',
        first ? (p.description.length > 320 ? p.description.substring(0, 320) : p.description) : '',
        v.image ?? '',
        'kg',
        first ? 'draft' : '',
      ]);
    }
    for (var i = 1; i < p.images.length; i++) {
      rows.add([
        for (final column in shopifyColumns)
          switch (column) {
            'Handle' => h,
            'Image Src' => p.images[i],
            'Image Position' => '${i + 1}',
            'Image Alt Text' => p.name,
            _ => '',
          },
      ]);
    }
  }
  return '${_csv(rows)}\r\n';
}

String? _feedAvailability(String? value) => switch ((value ?? '').toLowerCase()) {
  'instock' || 'in stock' || 'limitedavailability' || 'onlineonly' || 'instoreonly' => 'in_stock',
  'outofstock' || 'out of stock' || 'soldout' || 'discontinued' => 'out_of_stock',
  'preorder' || 'presale' => 'preorder',
  'backorder' => 'backorder',
  _ => null,
};

String? _feedGender(String? value) => switch ((value ?? '').toLowerCase()) {
  'female' || 'women' || 'womens' || "women's" || 'woman' => 'female',
  'male' || 'men' || 'mens' || "men's" || 'man' => 'male',
  'unisex' => 'unisex',
  _ => null,
};

const feedColumns = [
  'id', 'item_group_id', 'title', 'description', 'link', 'image_link', 'additional_image_link', //
  'availability', 'price', 'brand', 'gtin', 'mpn', 'identifier_exists', 'condition', 'google_product_category',
  'product_type', 'color', 'size', 'gender', 'age_group', 'material', 'pattern',
];

/// A tab-separated product data feed using the attribute names shared by
/// Google Merchant Center, Meta Commerce Manager, Pinterest and TikTok
/// catalogs. Unknown stock is left blank for you to set, never guessed.
String merchantFeed(List<Product> products) {
  String cell(String? value) => (value ?? '').replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  final rows = <List<String>>[feedColumns];
  for (final p in products) {
    final offer = p.displayOffer;
    final variants = p.variants.isEmpty ? [null] : p.variants;
    for (final (i, v) in variants.indexed) {
      final price = v?.price ?? offer?.price;
      final currency = v?.currency ?? offer?.currency;
      final gtin = v?.gtin ?? p.gtin;
      rows.add([
        v == null ? p.id : '${p.id}-${v.sku ?? i}',
        v == null ? '' : p.id,
        p.name.length > 150 ? p.name.substring(0, 150) : p.name,
        p.description.length > 5000 ? p.description.substring(0, 5000) : p.description,
        offer?.url.isNotEmpty == true ? offer!.url : p.sourceUrl,
        v?.image ?? p.images.firstOrNull,
        p.images.skip(1).take(10).join(','),
        _feedAvailability(v?.availability ?? offer?.availability),
        price == null || currency == null ? '' : '${_money(price)} $currency',
        p.brand,
        gtin,
        p.mpn,
        gtin == null && p.mpn == null ? 'no' : '',
        (p.condition ?? 'New').toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''),
        kindOf(p.category, p.productType)?.googleCategory ?? 'Apparel & Accessories',
        [p.category, ?p.productType].join(' > '),
        v?.color ?? p.color,
        v?.size ?? (p.sizes.length == 1 ? p.sizes.single : ''),
        _feedGender(p.gender),
        p.ageGroup?.toLowerCase(),
        p.material,
        p.pattern,
      ].map(cell).toList());
    }
  }
  return '${rows.map((r) => r.join('\t')).join('\n')}\n';
}

/// schema.org Product data: the most widely understood product format.
Map<String, dynamic> schemaOrg(List<Product> products) {
  Map<String, dynamic> offer(Offer o) => {
    '@type': 'Offer',
    if (o.url.isNotEmpty) 'url': o.url,
    'price': ?o.price,
    'priceCurrency': ?o.currency,
    if (o.availability != 'Unknown') 'availability': 'https://schema.org/${o.availability}',
    'seller': {'@type': 'Organization', 'name': o.seller},
  };
  Map<String, dynamic> clean(Map<String, dynamic> m) =>
      m..removeWhere((_, v) => v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty));
  return {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    'name': 'Vastra catalog',
    'dateCreated': DateTime.now().toUtc().toIso8601String(),
    'numberOfItems': products.length,
    'itemListElement': [
      for (final (i, p) in products.indexed)
        {
          '@type': 'ListItem',
          'position': i + 1,
          'item': clean({
            '@type': p.variants.isEmpty ? 'Product' : 'ProductGroup',
            'identifier': p.id,
            'name': p.name,
            'description': p.description,
            'url': p.sourceUrl,
            'image': p.images,
            'brand': {'@type': 'Brand', 'name': p.brand},
            'category': [p.category, ?p.productType].join(' > '),
            'additionalType': kindOf(p.category, p.productType)?.googleCategory,
            'sku': p.sku,
            'gtin': p.gtin,
            'mpn': p.mpn,
            'color': p.color,
            'material': p.material,
            'pattern': p.pattern,
            'size': p.sizes,
            'keywords': p.tags.join(', '),
            'itemCondition': p.condition == null ? null : 'https://schema.org/${p.condition}Condition',
            'audience': p.gender == null && p.ageGroup == null
                ? null
                : clean({'@type': 'PeopleAudience', 'suggestedGender': p.gender, 'suggestedAge': p.ageGroup}),
            'aggregateRating': p.rating == null
                ? null
                : clean({'@type': 'AggregateRating', 'ratingValue': p.rating, 'reviewCount': p.reviewCount}),
            'offers': p.offers.map(offer).toList(),
            'hasVariant': [
              for (final v in p.variants)
                clean({
                  '@type': 'Product',
                  'sku': v.sku,
                  'gtin': v.gtin,
                  'size': v.size,
                  'color': v.color,
                  'image': v.image,
                  'offers': v.price == null
                      ? null
                      : clean({
                          '@type': 'Offer',
                          'price': v.price,
                          'priceCurrency': v.currency,
                          'availability': v.availability == null ? null : 'https://schema.org/${v.availability}',
                        }),
                }),
            ],
            'dateModified': p.checkedAt,
            'isBasedOn': p.extraction,
          }),
        },
    ],
  };
}
