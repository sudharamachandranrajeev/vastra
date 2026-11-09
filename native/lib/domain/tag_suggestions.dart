import 'look.dart';
import 'product.dart';

/// A detail Vastra proposes for an item whose page did not state it. It is a
/// suggestion, kept apart from what the store published, and the owner
/// decides. [source] says where it came from.
class TagSuggestion {
  const TagSuggestion(this.field, this.value, this.source, this.reason);
  final String field, value, source, reason;
  String get key => '$field|$value';
}

const tagFields = ['color', 'material', 'pattern'];

const _colours = {
  'black': 'black',
  'white': 'white',
  'ivory': 'white',
  'cream': 'beige',
  'beige': 'beige',
  'tan': 'beige',
  'camel': 'beige',
  'khaki': 'beige',
  'brown': 'brown',
  'chocolate': 'brown',
  'grey': 'gray',
  'gray': 'gray',
  'charcoal': 'gray',
  'red': 'red',
  'burgundy': 'red',
  'maroon': 'red',
  'orange': 'orange',
  'yellow': 'yellow',
  'mustard': 'yellow',
  'green': 'green',
  'olive': 'green',
  'sage': 'green',
  'teal': 'teal',
  'blue': 'blue',
  'navy': 'navy',
  'purple': 'purple',
  'lilac': 'purple',
  'pink': 'pink',
  'blush': 'pink',
};

const _materials = {
  'cotton': 'cotton',
  'linen': 'linen',
  'wool': 'wool',
  'merino': 'wool',
  'cashmere': 'cashmere',
  'silk': 'silk',
  'satin': 'satin',
  'leather': 'leather',
  'suede': 'suede',
  'denim': 'denim',
  'polyester': 'polyester',
  'viscose': 'viscose',
  'nylon': 'nylon',
  'velvet': 'velvet',
  'corduroy': 'corduroy',
  'fleece': 'fleece',
  'knit': 'knit',
};

const _patterns = {
  'striped': 'striped',
  'stripe': 'striped',
  'floral': 'floral',
  'plaid': 'plaid',
  'tartan': 'plaid',
  'checked': 'checked',
  'gingham': 'checked',
  'polka dot': 'polka dot',
  'polka-dot': 'polka dot',
  'spotted': 'polka dot',
  'animal print': 'animal print',
  'leopard': 'animal print',
  'houndstooth': 'houndstooth',
  'paisley': 'paisley',
  'camo': 'camouflage',
  'camouflage': 'camouflage',
  'solid': 'solid',
};

String _words(Product p) =>
    ' ${[p.name, p.description, p.sourceCategory ?? '', p.tags.join(' '), Uri.tryParse(p.sourceUrl)?.pathSegments.join(' ') ?? ''].join(' ').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';

bool _empty(String? v) => v == null || v.trim().isEmpty;

/// Details the item's own words point to, for fields the page left empty. A
/// word is only used when it stands alone, and a name that mentions two
/// colours proposes both rather than choosing.
List<TagSuggestion> suggestFromText(Product p) {
  final text = _words(p);
  final out = <TagSuggestion>[];
  void scan(String field, bool missing, Map<String, String> vocab) {
    if (!missing) return;
    final seen = <String>{};
    for (final e in vocab.entries) {
      final word = e.key.replaceAll('-', ' ');
      if (text.contains(' $word ') && seen.add(e.value)) {
        out.add(TagSuggestion(field, e.value, 'text', 'The item says "${e.key}".'));
      }
    }
  }

  scan('color', _empty(p.color), _colours);
  scan('material', _empty(p.material), _materials);
  scan('pattern', _empty(p.pattern), _patterns);
  return out;
}

/// The colour a photo clearly shows, for an item that has none, and the
/// pattern when it is plain or busy enough to say so.
List<TagSuggestion> suggestFromLook(Product p, LookDescriptor look) {
  final out = <TagSuggestion>[];
  final colour = look.dominantColour;
  if (_empty(p.color) && colour != null) {
    out.add(TagSuggestion('color', colour, 'photo', 'Most of the photo is $colour.'));
  }
  if (_empty(p.pattern) && look.busy < 0.08 && colour != null) {
    out.add(const TagSuggestion('pattern', 'solid', 'photo', 'The photo shows one plain surface.'));
  }
  return out;
}

String fieldLabel(String field) => switch (field) {
  'color' => 'Colour',
  'material' => 'Material',
  _ => 'Pattern',
};

Product withTag(Product p, String field, String? value) => Product.fromJson({...p.toJson(), field: value});
