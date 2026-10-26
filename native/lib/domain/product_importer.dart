import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'product.dart';

class ImportFailure implements Exception {
  const ImportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProductImporter {
  ProductImporter(this.retailers, {http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final List<String> retailers;
  final http.Client Function() _clientFactory;
  Uri validate(String value) {
    final uri = Uri.tryParse(value.trim());
    if (value.length > 2048 ||
        uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw const ImportFailure('Use a complete HTTPS product link without credentials or a custom port.');
    }
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (!retailers.contains(host)) {
      throw const ImportFailure('This store is not supported yet. See the eligible stores below.');
    }
    final query = Map<String, dynamic>.from(uri.queryParametersAll)
      ..removeWhere((key, _) => RegExp(r'^(utm_|fbclid$|gclid$)', caseSensitive: false).hasMatch(key));
    return Uri.parse(
      '${uri.removeFragment().toString().split('?').first}${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
    );
  }

  Future<Product> fetch(String value) async {
    final source = validate(value);
    final client = _clientFactory();
    try {
      return await _fetch(client, source).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const ImportFailure('The store took too long to respond. Please try again.'),
      );
    } on ImportFailure {
      rethrow;
    } on Object {
      throw const ImportFailure('Could not reach the store. Check your connection and try again.');
    } finally {
      client.close();
    }
  }

  Future<Product> _fetch(http.Client client, Uri source) async {
    var uri = source;
    for (var redirects = 0; redirects <= 4; redirects++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll({
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent': 'Vastra/0.2 (+product-catalog-import)',
      });
      final response = await client.send(request);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        // Cancel instead of reading an unbounded redirect body.
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null) throw const ImportFailure('The store returned an incomplete redirect.');
        uri = validate(uri.resolve(location).toString());
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw ImportFailure(
          'The store could not share this page (HTTP ${response.statusCode}). Some stores restrict automated access.',
        );
      }
      if (!RegExp(
        r'text/html|application/xhtml\+xml',
        caseSensitive: false,
      ).hasMatch(response.headers['content-type'] ?? '')) {
        await response.stream.listen((_) {}).cancel();
        throw const ImportFailure('This link does not return a product web page.');
      }
      if ((response.contentLength ?? 0) > 2000000) {
        await response.stream.listen((_) {}).cancel();
        throw const ImportFailure('This product page is too large to import.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 2000000) {
          throw const ImportFailure('This product page is too large to import.');
        }
        bytes.addAll(chunk);
      }
      return extractProduct(utf8.decode(bytes, allowMalformed: true), uri);
    }
    throw const ImportFailure('This link redirected too many times. Paste the final product page link.');
  }
}

typedef Json = Map<String, dynamic>;
Json _object(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};
List<dynamic> _list(dynamic value) => value == null
    ? []
    : value is List
    ? value
    : [value];
String _text(dynamic value, [int limit = 2000]) {
  if (value is! String) return '';
  final text = (html.parseFragment(value).text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > limit ? text.substring(0, limit) : text;
}

List<Json> _nodes(dynamic value, [int depth = 0]) {
  if (depth > 12) return [];
  if (value is List) return value.expand((v) => _nodes(v, depth + 1)).toList();
  final node = _object(value);
  if (_list(node['@type']).any(
    (t) => [
      'Product',
      'ProductGroup',
      'https://schema.org/Product',
      'https://schema.org/ProductGroup',
    ].contains(t),
  )) {
    return [node];
  }
  return node.values.where((v) => v is Map || v is List).expand((v) => _nodes(v, depth + 1)).toList();
}

String? safeImage(dynamic value, Uri source) {
  if (value is! String || value.length > 4096) return null;
  try {
    final uri = source.resolve(value);
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !RegExp(r'^(?:[a-z0-9-]+\.)+[a-z]{2,}$', caseSensitive: false).hasMatch(uri.host) ||
        RegExp(
          r'(?:^|\.)(localhost|local|internal|test|invalid)$',
          caseSensitive: false,
        ).hasMatch(uri.host)) {
      return null;
    }
    return uri.toString();
  } on FormatException {
    return null;
  }
}

String inferCategory(String value) {
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(value);
  if (has(r'\bbody\b|lotion|shower|deodorant|soap')) return 'Body care';
  if (has(r'perfume|parfum|fragrance|cologne')) return 'Fragrance';
  if (has(r'serum|cosmetic|makeup|lipstick|skincare|cleanser|moisturi[sz]er')) return 'Beauty';
  if (has(r'shoe|sneaker|boot|sandal|loafer|trainer|runner')) return 'Footwear';
  if (has(r'bag|jewel|necklace|earring|\bring\b|watch|sunglass|belt|scarf|crossbody')) return 'Accessories';
  return 'Clothing';
}

Product extractProduct(String markup, Uri source) {
  final document = html.parse(markup);
  final metadata = <String, String>{};
  for (final element in document.querySelectorAll('meta')) {
    final key = element.attributes['property'] ?? element.attributes['name'];
    if (key != null) metadata[key.toLowerCase()] = element.attributes['content'] ?? '';
  }
  final nodes = <Json>[];
  for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      nodes.addAll(_nodes(jsonDecode(script.text)));
    } on FormatException {
      /* Product metadata remains available. */
    }
  }
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
      'This page contains multiple products. Paste a link to one specific product or variant.',
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
    _text(document.querySelector('title')?.text, 250),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  if (name.isEmpty) throw const ImportFailure('The store did not provide a product name.');
  final host = source.host.replaceFirst(RegExp(r'^www\.'), '');
  final brand = [
    _text(_object(node['brand'])['name'], 120),
    _text(node['brand'], 120),
    host,
  ].firstWhere((s) => s.isNotEmpty);
  final images = [
    ..._list(node['image']).map((v) => v is String ? v : _object(v)['url']),
    metadata['og:image'],
  ].map((v) => safeImage(v, source)).whereType<String>().toSet().take(8).toList();
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

  final offers = _list(node['offers'])
      .expand((v) {
        final o = _object(v);
        return o['@type'] == 'AggregateOffer' ? _list(o['offers']) : [o];
      })
      .take(30)
      .map((v) {
        final o = _object(v);
        final seller = _text(_object(o['seller'])['name'], 120);
        final availability = _text(o['availability'], 100).replaceFirst(RegExp(r'^https?://schema.org/'), '');
        return Offer(
          seller: seller.isEmpty ? host : seller,
          url: source.toString(),
          price: amount(o['price']),
          currency: currency(o['priceCurrency']),
          availability: availability.isEmpty ? 'Unknown' : availability,
        );
      })
      .toList();
  if (offers.isEmpty) {
    offers.add(
      Offer(
        seller: host,
        url: source.toString(),
        price: amount(metadata['product:price:amount']),
        currency: currency(metadata['product:price:currency']),
      ),
    );
  }
  final description = [
    _text(node['description']),
    _text(metadata['og:description']),
    _text(metadata['description']),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final sizes = [
    ..._list(node['size']),
    ..._list(node['hasVariant']).map((v) => _object(v)['size']),
  ].map((v) => v is num ? '$v' : _text(v, 50)).where((s) => s.isNotEmpty).toSet().take(30).toList();
  return Product(
    id: const Uuid().v4(),
    name: name,
    brand: brand,
    category: inferCategory('${_text(node['category'])} $name'),
    description: description,
    images: images,
    offers: offers,
    sourceUrl: source.toString(),
    checkedAt: DateTime.now().toUtc().toIso8601String(),
    sample: false,
    extraction: nodes.isEmpty ? 'metadata' : 'structured',
    material: _text(node['material'], 200).isEmpty ? null : _text(node['material'], 200),
    color: _text(node['color'], 120).isEmpty ? null : _text(node['color'], 120),
    sizes: sizes,
  );
}
