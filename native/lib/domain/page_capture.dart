import 'dart:convert';

import 'categorizer.dart';
import 'product.dart';
import 'product_importer.dart';

/// Runs in the shop page when the owner taps "Save to Vastra". It reads what
/// the browser is showing, after the shop's own scripts and any sign-in, so
/// prices are the ones on screen. Form fields, frames and scripts (except
/// product data) are removed first, so typed or prefilled personal details
/// are never read.
const captureScript = r'''(() => {
  const doc = document.documentElement.cloneNode(true);
  doc.querySelectorAll('input,textarea,select,form,iframe,noscript,svg,video,audio,canvas,template,style,link').forEach(e => e.remove());
  doc.querySelectorAll('script').forEach(s => { if ((s.type || '').toLowerCase() !== 'application/ld+json') s.remove(); });
  const html = doc.outerHTML.slice(0, 3000000);
  const images = Array.from(document.images)
    .filter(i => i.naturalWidth >= 200 && i.naturalHeight >= 200 && /^https:/.test(i.currentSrc || i.src))
    .sort((a, b) => b.naturalWidth * b.naturalHeight - a.naturalWidth * a.naturalHeight)
    .slice(0, 6).map(i => i.currentSrc || i.src);
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 4 && r.height > 4 && getComputedStyle(e).visibility !== 'hidden'; };
  const first = (selectors, min, max) => {
    for (const e of document.querySelectorAll(selectors)) {
      const t = (e.innerText || e.textContent || '').replace(/\s+/g, ' ').trim();
      if (t.length >= min && t.length <= max && (visible(e) || e.classList.contains('a-offscreen'))) return t;
    }
    return '';
  };
  const name = first('#productTitle, h1[itemprop=name], [itemprop=name] h1, .x-item-title__mainTitle, [data-testid*="product-title" i], [data-testid*="productTitle" i], .product-title, .product_title, .product-name, .pdp-title', 3, 300);
  const price = first('.apex-pricetopay-value, #corePrice_feature_div .a-offscreen, #corePriceDisplay_desktop_feature_div .a-offscreen, .priceToPay .a-offscreen, #price_inside_buybox, .x-price-primary, [itemprop=price], [data-testid*="price" i], .product-price, .price-current, .price', 1, 40);
  const brand = first('#bylineInfo, [itemprop=brand], .product-brand, .x-store-information__store-name', 1, 120);
  const h1 = Array.from(document.querySelectorAll('h1')).find(e => visible(e) && (e.innerText || '').trim().length >= 3);
  return JSON.stringify({
    name, price, brand,
    url: location.href,
    title: document.title,
    html,
    text: (document.body ? document.body.innerText : '').slice(0, 20000),
    selection: String(window.getSelection ? window.getSelection() : '').slice(0, 500),
    heading: h1 ? h1.innerText.slice(0, 300) : '',
    images
  });
})()''';

/// What the shop page showed when the owner saved it.
class ScreenCapture {
  const ScreenCapture({
    required this.url,
    this.title = '',
    this.html = '',
    this.text = '',
    this.selection = '',
    this.heading = '',
    this.name = '',
    this.price = '',
    this.brand = '',
    this.images = const [],
  });
  final String url, title, html, text, selection, heading;

  /// The product name, price and brand from the elements shops use for them,
  /// when the page has them.
  final String name, price, brand;
  final List<String> images;

  /// Accepts the script's result as the browser returns it. Android wraps
  /// strings in a second layer of JSON quoting.
  factory ScreenCapture.fromResult(Object? raw) {
    Object? value = raw;
    for (var i = 0; i < 2 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        break;
      }
    }
    if (value is! Map) throw const ImportFailure('Vastra could not read this page.');
    String s(String key, int limit) {
      final v = value as Map;
      final text = v[key] is String ? v[key] as String : '';
      return text.length > limit ? text.substring(0, limit) : text;
    }

    return ScreenCapture(
      url: s('url', 4096),
      title: s('title', 500),
      html: s('html', 3000000),
      text: s('text', 20000),
      selection: s('selection', 500),
      heading: s('heading', 300),
      name: s('name', 300),
      price: s('price', 40),
      brand: s('brand', 120),
      images: [
        for (final i in (value['images'] is List ? value['images'] as List : const []).take(6))
          if (i is String) i,
      ],
    );
  }
}

final _price = RegExp(
  r'(?<![A-Za-z])(US\$|CA\$|C\$|A\$|AU\$|NZ\$|HK\$|S\$|R\$|USD|EUR|GBP|INR|CAD|AUD|JPY|CHF|SEK|NOK|DKK|PLN|AED|SGD|Rs\.?|£|€|₹|¥|\$)\s?(\d{1,3}(?:[,.\s]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)',
);

const _symbols = {
  r'US$': 'USD',
  r'CA$': 'CAD',
  r'C$': 'CAD',
  r'A$': 'AUD',
  r'AU$': 'AUD',
  r'NZ$': 'NZD',
  r'HK$': 'HKD',
  r'S$': 'SGD',
  r'R$': 'BRL',
  'Rs': 'INR',
  'Rs.': 'INR',
  '£': 'GBP',
  '€': 'EUR',
  '₹': 'INR',
  '¥': 'JPY',
};

/// "1,299.00", "1.299,00" and "1 299" all read as numbers; the last
/// separator followed by one or two digits is the decimal point.
double? _amount(String raw) {
  final m = RegExp(r'^(.*?)[.,](\d{1,2})$').firstMatch(raw);
  final whole = (m?.group(1) ?? raw).replaceAll(RegExp(r'[^\d]'), '');
  if (whole.isEmpty) return null;
  return double.tryParse(m == null ? whole : '$whole.${m.group(2)}');
}

/// The first price shown in [text], preferring one after [near] (usually
/// the product name), with its ISO currency. A bare "$" follows the shop's
/// country where the address shows it.
(double, String)? priceFromText(String text, {String near = '', String host = ''}) {
  final start = near.isEmpty ? -1 : text.indexOf(near);
  final matches = _price.allMatches(text).toList();
  final match =
      (start < 0 ? null : matches.where((m) => m.start >= start).firstOrNull) ?? matches.firstOrNull;
  if (match == null) return null;
  final amount = _amount(match.group(2)!.trim());
  if (amount == null || amount <= 0) return null;
  final mark = match.group(1)!;
  final currency =
      _symbols[mark] ??
      (mark == r'$'
          ? (host.endsWith('.ca')
                ? 'CAD'
                : host.endsWith('.au')
                ? 'AUD'
                : 'USD')
          : mark);
  return (amount, currency);
}

/// Turns what the browser showed into a catalog item. The page's product data
/// is used when it has some; otherwise the name and price are read from the
/// visible text. Only public HTTPS pages are accepted.
Product productFromScreen(ScreenCapture capture, {Categorizer? categorizer}) {
  final uri = ProductImporter().validate(capture.url);
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final images = [for (final i in capture.images) ?safeImage(i, uri)];
  Product product;
  try {
    product = extractProduct(capture.html, uri, categorizer: categorizer);
  } on ImportFailure {
    final name = [
      capture.selection.trim(),
      capture.name.trim(),
      capture.heading.trim(),
    ].firstWhere((s) => s.length >= 3 && s.length <= 250, orElse: () => '');
    final base = linkProduct(uri, page: capture.html, hint: name, categorizer: categorizer);
    final brand = _brand(capture.brand);
    product = Product.fromJson({
      ...base.toJson(),
      if (name.isNotEmpty) 'name': name,
      if (brand.isNotEmpty) 'brand': brand,
      'extraction': 'screen',
    });
  }
  // A price the page's data left out is taken from the screen.
  if (product.offers.every((o) => o.price == null)) {
    final price =
        priceFromText(capture.price, host: host) ??
        priceFromText(capture.text, near: product.name, host: host);
    if (price != null) {
      product = Product.fromJson({
        ...product.toJson(),
        'offers': [Offer(seller: host, url: uri.toString(), price: price.$1, currency: price.$2).toJson()],
      });
    }
  }
  if (product.images.isEmpty && images.isNotEmpty) {
    product = Product.fromJson({...product.toJson(), 'images': images});
  }
  return product;
}

/// "Visit the Acme Store" and "Brand: Acme" both mean Acme.
String _brand(String raw) => raw
    .replaceFirst(RegExp(r'^(visit the|brand:)\s*', caseSensitive: false), '')
    .replaceFirst(RegExp(r'\s+store$', caseSensitive: false), '')
    .trim();
