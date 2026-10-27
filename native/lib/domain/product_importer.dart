import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'categorizer.dart';
import 'product.dart';

class ImportFailure implements Exception {
  const ImportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The first web link in text shared from another app, such as
/// "Look at this! https://store.com/p/1 via @store". Bare hosts such as
/// "store.com/p/1" count too, because some apps share links without a scheme.
String? sharedLink(String text) {
  final match =
      RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(text) ??
      RegExp(
        r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}/[^\s<>"]*',
        caseSensitive: false,
      ).firstMatch(text);
  if (match == null) return null;
  final link = match.group(0)!.replaceFirst(RegExp(r'''[).,;:!?'\]]+$'''), '');
  return link.contains('://') ? link : 'https://$link';
}

// Tracking parameters that never identify a product.
final _tracking = RegExp(
  r'^(utm_\w+|fbclid|gclid|gbraid|wbraid|msclkid|dclid|igshid|igsh|mc_cid|mc_eid|_ga|_gl|srsltid|si|ref_?|spm|scm|share_id|shareid)$',
  caseSensitive: false,
);

class ProductImporter {
  ProductImporter({http.Client Function()? clientFactory, Categorizer? categorizer})
    : _clientFactory = clientFactory ?? http.Client.new,
      categorizer = categorizer ?? Categorizer();
  final http.Client Function() _clientFactory;
  final Categorizer categorizer;

  /// Accepts any public store. Shared text is reduced to its link and plain
  /// HTTP is upgraded, because every app shares links differently.
  Uri validate(String value) {
    final link = sharedLink(value);
    final uri = link == null ? null : Uri.tryParse(link.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://'));
    if (value.length > 4096 ||
        uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !publicHost(uri.host)) {
      throw const ImportFailure('Share or paste a link to a product page on a public website.');
    }
    final query = Map<String, dynamic>.from(uri.queryParametersAll)..removeWhere((key, _) => _tracking.hasMatch(key));
    return Uri.parse(
      '${uri.removeFragment().toString().split('?').first}${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
    );
  }

  /// Fetches the page and gathers every detail it shares. A store that blocks
  /// automated access, or a page without product data, still becomes a
  /// catalog item from the link and whatever the page told us, so a shared
  /// find is never lost. Only an invalid link is refused.
  Future<Product> fetch(String value) async {
    final source = validate(value);
    // Apps often share "Product name - Store https://…"; the words name the find.
    final hint = _text(value.replaceFirst(sharedLink(value) ?? '', '').replaceAll(RegExp(r'https?://\S+'), ''), 250);
    final client = _clientFactory();
    try {
      final (page, uri) = await _page(client, source).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw const ImportFailure('The store took too long to respond.'),
      );
      try {
        return extractProduct(page, uri, categorizer: categorizer);
      } on ImportFailure {
        return linkProduct(uri, page: page, hint: hint, categorizer: categorizer);
      }
    } on ImportFailure catch (failure) {
      return linkProduct(source, note: failure.message, hint: hint, categorizer: categorizer);
    } on Object {
      return linkProduct(
        source,
        note: 'Could not reach the store. Refresh when you are online.',
        hint: hint,
        categorizer: categorizer,
      );
    } finally {
      client.close();
    }
  }

  Future<(String, Uri)> _page(http.Client client, Uri source) async {
    var uri = source;
    for (var redirects = 0; redirects <= 6; redirects++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll({
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en',
        'User-Agent': 'Vastra/0.3 (+https://github.com/sudharamachandranrajeev/vastra)',
      });
      final response = await client.send(request);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        // Cancel instead of reading an unbounded redirect body.
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null) throw const ImportFailure('The store returned an incomplete redirect.');
        // Short links (amzn.to, bit.ly and app share links) land on any store.
        uri = validate(uri.resolve(location).toString());
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw ImportFailure('The store did not share this page (HTTP ${response.statusCode}).');
      }
      if (!RegExp(
        r'text/html|application/xhtml\+xml',
        caseSensitive: false,
      ).hasMatch(response.headers['content-type'] ?? '')) {
        await response.stream.listen((_) {}).cancel();
        throw const ImportFailure('This link does not return a web page.');
      }
      if ((response.contentLength ?? 0) > 4000000) {
        await response.stream.listen((_) {}).cancel();
        throw const ImportFailure('This product page is too large to read.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 4000000) {
          throw const ImportFailure('This product page is too large to read.');
        }
        bytes.addAll(chunk);
      }
      return (utf8.decode(bytes, allowMalformed: true), uri);
    }
    throw const ImportFailure('This link redirected too many times.');
  }
}

/// A host on the public web: named, with a real top-level domain, not an
/// address literal or a local network name.
bool publicHost(String host) =>
    RegExp(r'^(?:[a-z0-9-]+\.)+[a-z]{2,}$', caseSensitive: false).hasMatch(host) &&
    !RegExp(r'(?:^|\.)(localhost|local|internal|lan|home|test|invalid|example)$', caseSensitive: false).hasMatch(host);

typedef Json = Map<String, dynamic>;
Json _object(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};
List<dynamic> _list(dynamic value) => value == null
    ? []
    : value is List
    ? value
    : [value];
String _text(dynamic value, [int limit = 2000]) {
  if (value is num) return '$value';
  if (value is! String) return '';
  final text = (html.parseFragment(value).text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > limit ? text.substring(0, limit) : text;
}

String? _optional(dynamic value, [int limit = 200]) {
  final text = _text(value, limit);
  return text.isEmpty ? null : text;
}

bool _typed(Json node, List<String> types) =>
    _list(node['@type']).any((t) => types.any((type) => t == type || t == 'https://schema.org/$type' || t == 'http://schema.org/$type'));

List<Json> _nodes(dynamic value, List<String> types, [int depth = 0]) {
  if (depth > 12) return [];
  if (value is List) return value.expand((v) => _nodes(v, types, depth + 1)).toList();
  final node = _object(value);
  if (_typed(node, types)) return [node];
  return node.values.where((v) => v is Map || v is List).expand((v) => _nodes(v, types, depth + 1)).toList();
}

String? safeImage(dynamic value, Uri source) {
  if (value is! String || value.length > 4096) return null;
  try {
    final uri = source.resolve(value.startsWith('//') ? 'https:$value' : value);
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443) || !publicHost(uri.host)) {
      return null;
    }
    return uri.toString();
  } on FormatException {
    return null;
  }
}

/// Vastra's top-level category for a product name or category text.
String inferCategory(String value) => Categorizer().classify(name: value).category;

class _Page {
  _Page(String markup) : document = html.parse(markup) {
    for (final element in document.querySelectorAll('meta')) {
      final key = element.attributes['property'] ?? element.attributes['name'] ?? element.attributes['itemprop'];
      if (key != null) metadata.putIfAbsent(key.toLowerCase(), () => element.attributes['content'] ?? '');
    }
    for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        json.add(jsonDecode(script.text));
      } on FormatException {
        /* Product metadata remains available. */
      }
    }
  }
  final dom.Document document;
  final metadata = <String, String>{};
  final json = <dynamic>[];

  List<Json> typed(List<String> types) => json.expand((j) => _nodes(j, types)).toList();
  String? meta(List<String> keys) =>
      keys.map((k) => metadata[k]).firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);

  /// The deepest breadcrumb trail, without "Home" and the product itself.
  String? breadcrumb(String productName) {
    final trails = typed(['BreadcrumbList'])
        .map(
          (list) =>
              (_list(list['itemListElement']).map(_object).toList()
                    ..sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0)))
                  .map((e) => _text(e['name'] ?? _object(e['item'])['name'], 80))
                  .where((n) => n.isNotEmpty && n.toLowerCase() != 'home' && n != productName)
                  .toList(),
        )
        .where((t) => t.isNotEmpty)
        .toList();
    if (trails.isEmpty) return null;
    trails.sort((a, b) => b.length.compareTo(a.length));
    return trails.first.join(' > ');
  }
}

Product extractProduct(String markup, Uri source, {Categorizer? categorizer}) {
  final page = _Page(markup);
  final metadata = page.metadata;
  final nodes = page.typed(['Product', 'ProductGroup', 'IndividualProduct']);
  bool matches(dynamic value) {
    if (value is! String || value.isEmpty) return false;
    try {
      return source.resolve(value).removeFragment().toString() == source.toString();
    } on FormatException {
      return false;
    }
  }

  bool primary(Json node) =>
      [node['url'], node['@id'], ..._list(node['offers']).map((v) => _object(v)['url'])].any(matches);
  final distinct = <String, Json>{
    for (final n in nodes)
      (_text(n['sku']).isNotEmpty
              ? _text(n['sku'])
              : _text(n['@id']).isNotEmpty
              ? _text(n['@id'])
              : _text(n['name'])):
          n,
  };
  final candidates = distinct.values.where(primary).toList();
  final variants = nodes
      .expand(
        (group) =>
            _list(group['hasVariant'])
                .map(_object)
                .where(primary)
                .map((variant) => <String, dynamic>{...group, ...variant}),
      )
      .toList();
  if (variants.length > 1 || (variants.isEmpty && candidates.length != 1 && distinct.length > 1)) {
    throw const ImportFailure(
      'This page contains multiple products. Share a link to one specific product or variant.',
    );
  }
  final node = variants.firstOrNull ?? candidates.firstOrNull ?? nodes.firstOrNull ?? <String, dynamic>{};
  if (nodes.isEmpty &&
      !(metadata['og:type'] ?? '').toLowerCase().contains('product') &&
      (metadata['product:price:amount'] ?? '').isEmpty) {
    throw const ImportFailure(
      'No product data was found. The store may block imports, or this may not be a product page.',
    );
  }
  final name = [
    _text(node['name'], 250),
    _text(metadata['og:title'], 250),
    _text(page.document.querySelector('title')?.text, 250),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  if (name.isEmpty) throw const ImportFailure('The store did not provide a product name.');
  final host = source.host.replaceFirst(RegExp(r'^www\.'), '');
  final brand = [
    _text(_object(node['brand'])['name'], 120),
    _text(node['brand'], 120),
    _text(metadata['product:brand'], 120),
    _text(metadata['og:site_name'], 120),
    host,
  ].firstWhere((s) => s.isNotEmpty);
  double? amount(dynamic value) {
    if (value is! num && value is! String) return null;
    if (value is String && !RegExp(r'^\d+(\.\d+)?$').hasMatch(value.trim())) return null;
    final result = double.tryParse('$value');
    return result != null && result.isFinite && result >= 0 ? result : null;
  }

  String? currency(dynamic value) {
    final code = _text(value, 20).toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : null;
  }

  String availability(dynamic value) =>
      _text(value, 100).replaceFirst(RegExp(r'^https?://schema.org/'), '');
  String? gtin(Json n) => [
    for (final key in ['gtin', 'gtin13', 'gtin12', 'gtin14', 'gtin8', 'isbn']) _text(n[key], 20),
  ].firstWhere((g) => RegExp(r'^\d{8,14}$').hasMatch(g), orElse: () => '').nonEmpty;

  final offers = _list(node['offers'])
      .expand((v) {
        final o = _object(v);
        return _typed(o, ['AggregateOffer']) && o['offers'] != null ? _list(o['offers']) : [o];
      })
      .take(30)
      .map((v) {
        final o = _object(v);
        final seller = _text(_object(o['seller'])['name'], 120);
        final stock = availability(o['availability']);
        return Offer(
          seller: seller.isEmpty ? host : seller,
          url: source.toString(),
          price: amount(o['price']) ?? amount(o['lowPrice']) ?? amount(_object(o['priceSpecification'])['price']),
          currency: currency(o['priceCurrency']) ?? currency(_object(o['priceSpecification'])['priceCurrency']),
          availability: stock.isEmpty ? 'Unknown' : stock,
        );
      })
      .toList();
  if (offers.isEmpty) {
    offers.add(
      Offer(
        seller: host,
        url: source.toString(),
        price: amount(page.meta(['product:price:amount', 'og:price:amount', 'price'])),
        currency: currency(page.meta(['product:price:currency', 'og:price:currency', 'pricecurrency'])),
        availability: page.meta(['product:availability', 'og:availability']) ?? 'Unknown',
      ),
    );
  }
  final variantList = _list(node['hasVariant'])
      .map(_object)
      .take(100)
      .map((v) {
        final offer = _object(_list(v['offers']).firstOrNull);
        final stock = availability(offer['availability']);
        return Variant(
          sku: _optional(v['sku'], 80),
          gtin: gtin(v),
          size: _optional(v['size'], 50),
          color: _optional(v['color'], 80),
          price: amount(offer['price']),
          currency: currency(offer['priceCurrency']),
          availability: stock.isEmpty ? null : stock,
          image: _list(v['image']).map((i) => safeImage(i is String ? i : _object(i)['url'], source)).nonNulls.firstOrNull,
        );
      })
      .toList();
  final images = [
    ..._list(node['image']).map((v) => v is String ? v : _object(v)['url'] ?? _object(v)['contentUrl']),
    metadata['og:image'],
    metadata['og:image:secure_url'],
    metadata['twitter:image'],
    ...variantList.map((v) => v.image),
  ].map((v) => safeImage(v, source)).whereType<String>().toSet().take(12).toList();
  final description = [
    _text(node['description']),
    _text(metadata['og:description']),
    _text(metadata['description']),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final sizes = [
    ..._list(node['size']),
    ...variantList.map((v) => v.size),
  ].map((v) => v is num ? '$v' : _text(v, 50)).where((s) => s.isNotEmpty).toSet().take(30).toList();
  final audience = _object(node['audience']);
  final rating = _object(node['aggregateRating']);
  final sourceCategory = [
    _list(node['category']).map((c) => _text(c is String ? c : _object(c)['name'], 200)).where((c) => c.isNotEmpty).join(' > '),
    page.breadcrumb(name) ?? '',
    _text(metadata['product:category'], 200),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final kind = (categorizer ?? Categorizer()).classify(
    name: name,
    sourceCategory: sourceCategory,
    description: description,
  );
  final color = _optional(node['color'], 120) ?? _optional(metadata['product:color'], 120);
  return Product(
    id: const Uuid().v4(),
    name: name,
    brand: brand,
    category: kind.category,
    productType: kind.type,
    sourceCategory: sourceCategory.isEmpty ? null : sourceCategory,
    description: description,
    images: images,
    offers: offers,
    sourceUrl: source.toString(),
    checkedAt: DateTime.now().toUtc().toIso8601String(),
    sample: false,
    extraction: nodes.isEmpty ? 'metadata' : 'structured',
    material: _optional(node['material']),
    color: color,
    sizes: sizes,
    sku: _optional(node['sku'], 80) ?? _optional(metadata['product:retailer_item_id'], 80),
    gtin: gtin(node),
    mpn: _optional(node['mpn'], 80),
    gender: _optional(audience['suggestedGender'] ?? node['gender'] ?? metadata['product:target_gender'], 40),
    ageGroup: _optional(node['ageGroup'] ?? metadata['product:age_group'], 40),
    pattern: _optional(node['pattern'], 80),
    condition: _optional(availability(node['itemCondition']).replaceFirst(RegExp(r'Condition$'), ''), 40),
    rating: amount(rating['ratingValue']),
    reviewCount: amount(rating['reviewCount'] ?? rating['ratingCount'])?.toInt(),
    tags: _list(node['keywords'])
        .expand((k) => _text(k, 500).split(','))
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty && k.length <= 40)
        .toSet()
        .take(20)
        .toList(),
    variants: variantList,
  );
}

/// A catalog item from a link alone, enriched by any title, image and
/// description the page shared. [note] says why no product data was read.
Product linkProduct(Uri source, {String? page, String? note, String hint = '', Categorizer? categorizer}) {
  final parsed = page == null ? null : _Page(page);
  final host = source.host.replaceFirst(RegExp(r'^www\.'), '');
  // "/products/linen-wrap-dress-123" names the product when the page would not.
  final slug = source.pathSegments.reversed
      .map((s) => Uri.decodeComponent(s).replaceAll(RegExp(r'[-_+]+'), ' ').replaceAll(RegExp(r'\.\w+$'), '').trim())
      .firstWhere((s) => RegExp(r'[a-zA-Z]{3}').hasMatch(s) && !RegExp(r'^(p|dp|product|products|item|itm)$').hasMatch(s), orElse: () => '');
  final name = [
    _text(parsed?.meta(['og:title', 'twitter:title']), 250),
    _text(parsed?.document.querySelector('title')?.text, 250),
    hint,
    slug.isEmpty ? '' : '${slug[0].toUpperCase()}${slug.substring(1)}',
    'Find from $host',
  ].firstWhere((s) => s.isNotEmpty);
  final description = _text(parsed?.meta(['og:description', 'description', 'twitter:description']));
  final kind = (categorizer ?? Categorizer()).classify(name: name, description: description);
  return Product(
    id: const Uuid().v4(),
    name: name,
    brand: _text(parsed?.meta(['og:site_name']), 120).nonEmpty ?? host,
    category: kind.category,
    productType: kind.type,
    description: description.isEmpty ? (note ?? '') : description,
    images: [
      parsed?.meta(['og:image', 'og:image:secure_url', 'twitter:image']),
    ].map((v) => safeImage(v, source)).whereType<String>().toList(),
    offers: [Offer(seller: host, url: source.toString())],
    sourceUrl: source.toString(),
    checkedAt: DateTime.now().toUtc().toIso8601String(),
    sample: false,
    extraction: 'link',
  );
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}
