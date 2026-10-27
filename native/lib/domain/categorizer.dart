import 'dart:math' as math;

/// A product type and where it sits in Vastra's categories and in the
/// Google product taxonomy (used by Merchant Center, Meta and Pinterest feeds).
class ProductKind {
  const ProductKind(this.category, this.type, this.pattern, this.googleCategory);
  final String category, type, pattern, googleCategory;
}

const _apparel = 'Apparel & Accessories';
const _clothing = '$_apparel > Clothing';
const _cosmetics = 'Health & Beauty > Personal Care > Cosmetics';

const kinds = [
  ProductKind('Body care', 'Body wash', r'shower|body ?wash|bath gel', '$_cosmetics > Bath & Body'),
  ProductKind('Body care', 'Body lotion', r'lotion|body (?:butter|cream|oil)', '$_cosmetics > Bath & Body'),
  ProductKind(
    'Body care',
    'Deodorant',
    r'deodorant|antiperspirant',
    'Health & Beauty > Personal Care > Deodorant & Anti-Perspirant',
  ),
  ProductKind('Body care', 'Soap', r'soap|body scrub', '$_cosmetics > Bath & Body'),
  ProductKind(
    'Fragrance',
    'Perfume',
    r'perfume|parfum|eau de|fragrance|cologne|attar|body mist',
    '$_cosmetics > Perfume & Cologne',
  ),
  ProductKind('Beauty', 'Serum', r'serum|essence|ampoule', '$_cosmetics > Skin Care'),
  ProductKind('Beauty', 'Cleanser', r'cleanser|face ?wash|micellar', '$_cosmetics > Skin Care'),
  ProductKind('Beauty', 'Moisturiser', r'moisturi[sz]er|face cream|night cream|gel cream', '$_cosmetics > Skin Care'),
  ProductKind('Beauty', 'Sun care', r'sunscreen|sun ?cream|spf', '$_cosmetics > Skin Care'),
  ProductKind('Beauty', 'Skin care', r'skin ?care|toner|face mask|exfoliant|retinol', '$_cosmetics > Skin Care'),
  ProductKind(
    'Beauty',
    'Makeup',
    r'makeup|lipstick|lip (?:gloss|tint|balm)|mascara|foundation|concealer|blush|eyeliner|eyeshadow|kajal|cosmetic',
    '$_cosmetics > Makeup',
  ),
  ProductKind(
    'Beauty',
    'Hair care',
    r'shampoo|conditioner|hair (?:oil|mask|serum|spray)',
    'Health & Beauty > Personal Care > Hair Care',
  ),
  ProductKind('Footwear', 'Sneakers', r'sneakers?|trainers?|runners?|running shoes?', '$_apparel > Shoes'),
  ProductKind('Footwear', 'Boots', r'boots?|booties', '$_apparel > Shoes'),
  ProductKind('Footwear', 'Sandals', r'sandals?|slides|flip[- ]?flops?|chappals?|kolhapuris?', '$_apparel > Shoes'),
  ProductKind('Footwear', 'Heels', r'heels?|pumps|stilettos?|wedges', '$_apparel > Shoes'),
  ProductKind(
    'Footwear',
    'Flats',
    r'loafers?|flats|ballet|mules?|moccasins?|juttis?|mojaris?|espadrilles?',
    '$_apparel > Shoes',
  ),
  ProductKind('Footwear', 'Shoes', r'shoes?|footwear', '$_apparel > Shoes'),
  ProductKind(
    'Accessories',
    'Bags',
    r'bags?|totes?|backpacks?|crossbody|clutch|purse|handbags?|wallets?|satchel',
    '$_apparel > Handbags, Wallets & Cases',
  ),
  ProductKind(
    'Accessories',
    'Jewellery',
    r'jewel(?:le)?ry|jewel|necklaces?|earrings?|rings?|bracelets?|bangles?|pendants?|anklets?|jhumkas?',
    '$_apparel > Jewelry',
  ),
  ProductKind('Accessories', 'Watches', r'watch(?:es)?|smartwatch', '$_apparel > Jewelry > Watches'),
  ProductKind('Accessories', 'Sunglasses', r'sunglass(?:es)?|eyewear', '$_apparel > Clothing Accessories > Sunglasses'),
  ProductKind('Accessories', 'Belts', r'belts?', '$_apparel > Clothing Accessories > Belts'),
  ProductKind(
    'Accessories',
    'Scarves',
    r'scarf|scarves|stoles?|dupattas?|shawls?',
    '$_apparel > Clothing Accessories > Scarves & Shawls',
  ),
  ProductKind('Accessories', 'Hats', r'hats?|caps?|beanies?', '$_apparel > Clothing Accessories > Hats'),
  ProductKind('Clothing', 'Dresses', r'dress(?:es)?|gowns?|frocks?', '$_clothing > Dresses'),
  ProductKind(
    'Clothing',
    'Ethnic wear',
    r'sarees?|saris?|salwar|sherwanis?|lehengas?|anarkali|kurta sets?',
    '$_clothing > Traditional & Ceremonial Clothing',
  ),
  ProductKind(
    'Clothing',
    'Knitwear',
    r'sweaters?|jumpers?|cardigans?|pullovers?|hoodies?|sweatshirts?',
    '$_clothing > Shirts & Tops',
  ),
  ProductKind(
    'Clothing',
    'Outerwear',
    r'jackets?|coats?|blazers?|parkas?|gilets?|trench',
    '$_clothing > Outerwear > Coats & Jackets',
  ),
  ProductKind(
    'Clothing',
    'Tops',
    r'shirts?|t-shirts?|tees?|tops?|blouses?|tanks?|camisoles?|polos?|kurtis?|kurtas?|tunics?',
    '$_clothing > Shirts & Tops',
  ),
  ProductKind('Clothing', 'Trousers', r'trousers?|pants|jeans|chinos?|leggings|joggers', '$_clothing > Pants'),
  ProductKind('Clothing', 'Shorts', r'shorts', '$_clothing > Shorts'),
  ProductKind('Clothing', 'Skirts', r'skirts?', '$_clothing > Skirts'),
  ProductKind(
    'Clothing',
    'Jumpsuits',
    r'jumpsuits?|playsuits?|rompers?|dungarees|overalls',
    '$_clothing > One-Pieces',
  ),
  ProductKind('Clothing', 'Swimwear', r'swim\w*|bikinis?', '$_clothing > Swimwear'),
  ProductKind(
    'Clothing',
    'Underwear',
    r'bras?|briefs|boxers|lingerie|socks|underwear',
    '$_clothing > Underwear & Socks',
  ),
  ProductKind(
    'Clothing',
    'Sleepwear',
    r'pyjamas?|pajamas?|nightwear|loungewear|nightdress',
    '$_clothing > Sleepwear & Loungewear',
  ),
];

final _patterns = [for (final k in kinds) RegExp('\\b(?:${k.pattern})\\b', caseSensitive: false)];

ProductKind? kindOf(String category, String? type) =>
    kinds.where((k) => k.category == category && k.type == type).firstOrNull ??
    kinds.where((k) => k.category == category).firstOrNull;

/// The kind named last in [text]. Product titles put the head noun last, so
/// "Cap sleeve dress" is a dress and "Dress watch" is a watch.
ProductKind? _lastNamed(String text) {
  ProductKind? best;
  var at = -1;
  for (var i = 0; i < kinds.length; i++) {
    for (final m in _patterns[i].allMatches(text)) {
      if (m.start > at) {
        at = m.start;
        best = kinds[i];
      }
    }
  }
  return best;
}

ProductKind? _firstNamed(String text) {
  ProductKind? best;
  var at = text.length;
  for (var i = 0; i < kinds.length; i++) {
    final m = _patterns[i].firstMatch(text);
    if (m != null && m.start < at) {
      at = m.start;
      best = kinds[i];
    }
  }
  return best;
}

class Classification {
  const Classification(this.category, this.type, this.evidence);
  final String category;
  final String? type;

  /// 'name', 'source category', 'description', 'your corrections' or 'default'.
  final String evidence;
}

/// Puts products in a category and type. Nothing leaves the device.
///
/// Order of evidence: the product name, the seller's category or breadcrumb,
/// then a naive Bayes vote learned from categories the user corrected, then
/// the description. The same approach as Artha's transaction categorizer.
class Categorizer {
  Categorizer([Iterable<(String text, String category, String? type)> corrections = const []]) {
    for (final (text, category, type) in corrections) {
      learn(text, category, type);
    }
  }

  final _tokenCounts = <String, Map<String, int>>{};
  final _labelTotals = <String, int>{};
  final _labelExamples = <String, int>{};
  final _vocab = <String>{};
  var _examples = 0;

  static String _label(String category, String? type) => '$category\u0000${type ?? ''}';

  void learn(String text, String category, String? type) {
    final tokens = tokenize(text);
    if (tokens.isEmpty) return;
    final label = _label(category, type);
    final counts = _tokenCounts.putIfAbsent(label, () => {});
    for (final t in tokens) {
      counts.update(t, (v) => v + 1, ifAbsent: () => 1);
      _vocab.add(t);
    }
    _labelTotals.update(label, (v) => v + tokens.length, ifAbsent: () => tokens.length);
    _labelExamples.update(label, (v) => v + 1, ifAbsent: () => 1);
    _examples++;
  }

  Classification classify({required String name, String? sourceCategory, String description = ''}) {
    final byName = _lastNamed(name);
    if (byName != null) return Classification(byName.category, byName.type, 'name');
    final bySource = _lastNamed(sourceCategory ?? '');
    if (bySource != null) return Classification(bySource.category, bySource.type, 'source category');
    final learned = _vote('$name ${sourceCategory ?? ''}');
    if (learned != null) return learned;
    final byDescription = _firstNamed(description);
    if (byDescription != null) return Classification(byDescription.category, byDescription.type, 'description');
    return const Classification('Clothing', null, 'default');
  }

  // Naive Bayes with Laplace smoothing, scored in log space.
  Classification? _vote(String text) {
    final tokens = tokenize(text);
    if (tokens.isEmpty || _examples == 0) return null;
    String? bestLabel;
    var best = double.negativeInfinity, second = double.negativeInfinity;
    for (final label in _labelTotals.keys) {
      final counts = _tokenCounts[label]!;
      var score = math.log(_labelExamples[label]! / _examples);
      for (final t in tokens) {
        score += math.log(((counts[t] ?? 0) + 1) / (_labelTotals[label]! + _vocab.length));
      }
      if (score > best) {
        second = best;
        best = score;
        bestLabel = label;
      } else if (score > second) {
        second = score;
      }
    }
    // Only speak when the winner clearly beats the runner-up and has seen a known word.
    if (bestLabel == null || !tokens.any(_tokenCounts[bestLabel]!.containsKey)) return null;
    if (second.isFinite && best - second < math.log(2)) return null;
    final [category, type] = bestLabel.split('\u0000');
    return Classification(category, type.isEmpty ? null : type, 'your corrections');
  }
}

const _stopWords = {
  'the', 'and', 'for', 'with', 'from', 'this', 'that', 'your', 'our', 'new', 'in', 'of', 'a', 'an', 'to', 'by', //
  'on', 'at', 'is', 'it', 'or', 'all', 'buy', 'online', 'shop', 'sale', 'free', 'women', 'men', 'size',
};

List<String> tokenize(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.length > 1 && !_stopWords.contains(t) && !RegExp(r'^\d+$').hasMatch(t))
    .map((t) => t.length > 4 && t.endsWith('s') && !t.endsWith('ss') ? t.substring(0, t.length - 1) : t)
    .toList();
