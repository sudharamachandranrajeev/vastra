import 'page_capture.dart';

/// What OCR found in a screenshot: the lines worth searching for, any price,
/// and any shop links that were visible.
class ScreenshotText {
  const ScreenshotText({required this.lines, required this.candidates, this.price, this.links = const []});
  final List<String> lines, candidates;
  final (double, String)? price;
  final List<Uri> links;

  /// The search Vastra starts with: the two best lines, which the owner edits.
  String get query => candidates.take(2).join(' ').trim();
}

final _ui = RegExp(
  r'^(like[sd]?|share|follow(ing)?|reply|send|save|more|see more|view all|buy now|shop now|add to (cart|bag|basket)|'
  r'in stock|instagram|tiktok|pinterest|facebook|whatsapp|messages|free (delivery|shipping|returns)|sponsored|ad|home|search|menu|back|cancel|done|ok|\d+ (likes|views|comments))$',
  caseSensitive: false,
);

/// Reads OCR [lines]. Status-bar times, counters, buttons and price lines are
/// not search words.
ScreenshotText readScreenshot(List<String> lines) {
  final clean = [
    for (final l in lines)
      if (l.replaceAll(RegExp(r'\s+'), ' ').trim() case final t when t.isNotEmpty) t,
  ];
  final text = clean.join('\n');
  final links = <Uri>{
    for (final m in RegExp(
      r'(?:https?://|www\.)[^\s<>"]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|co\.uk|in|de|fr|it|es|ca|com\.au|shop|store)/[^\s<>"]+',
      caseSensitive: false,
    ).allMatches(text))
      if (Uri.tryParse(m.group(0)!.startsWith('http') ? m.group(0)! : 'https://${m.group(0)!}') case final u?
          when u.host.contains('.'))
        u.replace(scheme: 'https'),
  };
  bool wordy(String l) {
    final letters = RegExp(r'[A-Za-zÀ-ɏ]').allMatches(l).length;
    return l.length >= 4 &&
        letters >= l.length * 0.6 &&
        RegExp(r'[A-Za-z]{3}').hasMatch(l) &&
        !_ui.hasMatch(l) &&
        priceFromText(l) == null &&
        !RegExp(r'https?://|www\.|@|#').hasMatch(l);
  }

  // Screen order is kept: a product name usually sits just above its price.
  // Long sentences are captions and comments, not names.
  final candidates = clean.where((l) => wordy(l) && l.split(' ').length <= 14).toSet().toList();
  return ScreenshotText(
    lines: clean,
    candidates: candidates.take(8).toList(),
    price: priceFromText(text),
    links: links.toList(),
  );
}
