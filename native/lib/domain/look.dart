import 'dart:math';
import 'dart:typed_data';

/// What a photo looks like to Vastra: how much of each colour it holds and how
/// busy it is. It is worked out on the device from a tiny copy of the photo,
/// so similar items are found without sending any picture anywhere. It
/// matches colour and pattern, not shape or the kind of garment.
const colourNames = [
  'black',
  'gray',
  'white',
  'beige',
  'brown',
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'navy',
  'purple',
  'pink',
];

class LookDescriptor {
  const LookDescriptor(this.shares, this.busy);

  /// Share of the garment in each of [colourNames], adding up to 1.
  final List<double> shares;

  /// 0 for a plain surface, towards 1 for prints, stripes and texture.
  final double busy;

  List<double> toJson() => [...shares, busy];
  factory LookDescriptor.fromJson(List<dynamic> json) {
    if (json.length != colourNames.length + 1) throw const FormatException('Unknown look format.');
    final numbers = json.map((e) => (e as num).toDouble()).toList();
    return LookDescriptor(numbers.sublist(0, colourNames.length), numbers.last);
  }

  /// The colour that fills most of the garment, if one clearly does.
  String? get dominantColour {
    var best = 0;
    for (var i = 1; i < shares.length; i++) {
      if (shares[i] > shares[best]) best = i;
    }
    return shares[best] >= 0.4 ? colourNames[best] : null;
  }
}

/// The colour class of one pixel.
int colourClass(int r, int g, int b) {
  final mx = max(r, max(g, b)) / 255, mn = min(r, min(g, b)) / 255, d = mx - mn;
  final v = mx, s = mx == 0 ? 0.0 : d / mx;
  if (v < 0.18) return 0;
  if (s < 0.12) return v > 0.85 ? 2 : 1;
  final double h;
  if (d == 0) {
    h = 0;
  } else if (mx == r / 255) {
    h = (60 * (((g - b) / 255 / d) % 6)).toDouble();
  } else if (mx == g / 255) {
    h = 60 * ((b - r) / 255 / d + 2);
  } else {
    h = 60 * ((r - g) / 255 / d + 4);
  }
  final hue = (h + 360) % 360;
  if (hue < 15 || hue >= 345) return s < 0.45 && v > 0.75 ? 13 : 5;
  if (hue < 45) {
    if (v < 0.6) return 4;
    return s < 0.4 ? 3 : 6;
  }
  if (hue < 70) {
    if (v < 0.55) return 4;
    return s < 0.35 ? 3 : 7;
  }
  if (hue < 165) return 8;
  if (hue < 200) return 9;
  if (hue < 255) return v < 0.45 ? 11 : 10;
  if (hue < 300) return 12;
  return 13;
}

/// Describes a small RGBA image. The product is usually in the middle of
/// the photo, so the middle counts most. Near-white pixels around the edge
/// are skipped as background, and see-through pixels everywhere.
LookDescriptor describePixels(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    throw const FormatException('The photo could not be read.');
  }
  bool middle(int x, int y) => x >= width * 0.2 && x < width * 0.8 && y >= height * 0.15 && y < height * 0.85;
  bool white(int i) => rgba[i * 4] >= 235 && rgba[i * 4 + 1] >= 235 && rgba[i * 4 + 2] >= 235;
  List<double> weights(bool skipWhite) => [
    for (var i = 0; i < width * height; i++)
      if (rgba[i * 4 + 3] < 128)
        0
      else if (middle(i % width, i ~/ width))
        1
      else if (skipWhite && white(i))
        0
      else
        0.35,
  ];
  var weight = weights(true);
  var total = weight.fold<double>(0, (a, b) => a + b);
  // A photo that is nearly all white is a white garment; count it all.
  if (total < width * height * 0.08) {
    weight = weights(false);
    total = weight.fold<double>(0, (a, b) => a + b);
  }
  if (total == 0) throw const FormatException('The photo has nothing to look at.');
  final shares = List<double>.filled(colourNames.length, 0);
  double luma(int i) => 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
  var edge = 0.0, edges = 0.0;
  void pair(int i, int j) {
    final w = min(weight[i], weight[j]);
    if (w == 0) return;
    edge += w * (luma(i) - luma(j)).abs();
    edges += w;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (weight[i] == 0) continue;
      shares[colourClass(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2])] += weight[i];
      if (x + 1 < width) pair(i, i + 1);
      if (y + 1 < height) pair(i, i + width);
    }
  }
  return LookDescriptor([
    for (final s in shares) s / total,
  ], edges == 0 ? 0 : min(1.0, edge / edges / 255 * 6));
}

/// 0 for the same look, towards 1 for nothing in common.
double lookDistance(LookDescriptor a, LookDescriptor b) {
  var overlap = 0.0;
  for (var i = 0; i < a.shares.length; i++) {
    overlap += min(a.shares[i], b.shares[i]);
  }
  return 0.8 * (1 - overlap) + 0.2 * (a.busy - b.busy).abs();
}

/// Product ids closest in look to [query], nearest first. Matches farther
/// than [within] are dropped rather than padded out.
List<(String, double)> rankByLook(
  LookDescriptor query,
  Map<String, LookDescriptor> candidates, {
  int limit = 12,
  double within = 0.6,
}) {
  final ranked = [for (final e in candidates.entries) (e.key, lookDistance(query, e.value))]
    ..removeWhere((e) => e.$2 > within)
    ..sort((a, b) => a.$2.compareTo(b.$2));
  return ranked.take(limit).toList();
}

/// A plain-words reading of how close a match is.
String closeness(double distance) => distance < 0.2
    ? 'Very close'
    : distance < 0.4
    ? 'Close'
    : 'Loosely similar';
