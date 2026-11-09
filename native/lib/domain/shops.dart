/// Shops Vastra's browser can search directly. The owner picks their country's
/// Amazon and eBay; any other shop opens at its address.
const amazonSites = [
  'amazon.com',
  'amazon.co.uk',
  'amazon.in',
  'amazon.ca',
  'amazon.com.au',
  'amazon.de',
  'amazon.fr',
  'amazon.it',
  'amazon.es',
  'amazon.nl',
  'amazon.ae',
  'amazon.sg',
  'amazon.co.jp',
];

const ebaySites = [
  'ebay.com',
  'ebay.co.uk',
  'ebay.ca',
  'ebay.com.au',
  'ebay.de',
  'ebay.fr',
  'ebay.it',
  'ebay.es',
  'ebay.ie',
];

class ShopSearch {
  const ShopSearch(this.name, this.search);
  final String name;
  final Uri Function(String query) search;
}

List<ShopSearch> shopSearches({String amazon = 'amazon.com', String ebay = 'ebay.com'}) => [
  ShopSearch('Amazon', (q) => Uri.https('www.$amazon', '/s', {'k': q})),
  ShopSearch('eBay', (q) => Uri.https('www.$ebay', '/sch/i.html', {'_nkw': q})),
  ShopSearch('Google Shopping', (q) => Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': q})),
  ShopSearch('Etsy', (q) => Uri.https('www.etsy.com', '/search', {'q': q})),
  ShopSearch('Pinterest', (q) => Uri.https('www.pinterest.com', '/search/pins/', {'q': q})),
];

/// An address typed into the browser bar: "zara.com" becomes https.
Uri? shopAddress(String value) {
  final text = value.trim();
  if (text.isEmpty || text.contains(' ')) return null;
  final uri = Uri.tryParse(
    RegExp(r'^https?://', caseSensitive: false).hasMatch(text) ? text : 'https://$text',
  );
  if (uri == null || !uri.host.contains('.')) return null;
  return uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
}

/// Pages the browser may open. Other schemes (app links, files, scripts) are
/// refused so a shop page cannot leave the browser or reach the device.
bool browsable(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && ((uri.scheme == 'https' && uri.host.isNotEmpty) || url == 'about:blank');
}
