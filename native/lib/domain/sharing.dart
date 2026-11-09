import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'categorizer.dart';
import 'product.dart';
import 'product_importer.dart';

/// Sharing a collection without an account or a server: a single web page
/// anyone can open, and a small file another Vastra can open. Neither holds
/// anything private: no price paid, wears, sizes bought or fit notes.

const _maxItems = 500, _maxBytes = 2 * 1024 * 1024;

class ShareItem {
  const ShareItem({
    required this.name,
    required this.url,
    this.brand = '',
    this.image,
    this.price,
    this.currency = '',
  });
  final String name, brand, url, currency;
  final String? image;
  final double? price;

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'url': url,
    if (image != null) 'image': image,
    if (price != null) 'price': price,
    if (currency.isNotEmpty) 'currency': currency,
  };
}

class SharedList {
  const SharedList({required this.name, this.message = '', required this.items});
  final String name, message;
  final List<ShareItem> items;

  /// Short and stable for the same list, so claims only match their own page.
  String get id =>
      sha256.convert(utf8.encode('$name\n${items.map((i) => i.url).join('\n')}')).toString().substring(0, 8);
}

/// What a collection shares about [products]. Prices are optional.
SharedList sharedListFrom(String name, List<Product> products, {String message = '', bool prices = true}) =>
    SharedList(
      name: name,
      message: message.trim(),
      items: [
        for (final p in products)
          if (!p.sample && p.sourceUrl.startsWith('https://'))
            ShareItem(
              name: p.name,
              brand: p.brand,
              url: p.sourceUrl,
              image: p.images.where((i) => i.startsWith('https://')).firstOrNull,
              price: prices ? p.offers.where((o) => o.price != null).firstOrNull?.price : null,
              currency: prices ? (p.offers.where((o) => o.price != null).firstOrNull?.currency ?? '') : '',
            ),
      ],
    );

String shareFile(SharedList list) => const JsonEncoder.withIndent('  ').convert({
  'vastraList': 1,
  'name': list.name,
  if (list.message.isNotEmpty) 'message': list.message,
  'items': [for (final i in list.items) i.toJson()],
});

/// Reads a shared list file. Anything unsafe or malformed is dropped item by
/// item; a file that is not a Vastra list at all is refused.
SharedList parseSharedList(String text) {
  const notList = FormatException('This file is not a Vastra wish list.');
  if (text.length > _maxBytes) throw const FormatException('This wish list file is too large.');
  final Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    throw notList;
  }
  if (data is! Map || data['vastraList'] != 1 || data['items'] is! List) throw notList;
  String clip(Object? v, int n) => v is String ? v.trim().substring(0, v.trim().length.clamp(0, n)) : '';
  final importer = ProductImporter();
  final items = <ShareItem>[];
  for (final raw in (data['items'] as List).take(_maxItems)) {
    if (raw is! Map) continue;
    final name = clip(raw['name'], 200);
    final String url;
    try {
      url = importer.validate(clip(raw['url'], 2000)).toString();
    } on ImportFailure {
      continue;
    }
    if (name.isEmpty) continue;
    final image = clip(raw['image'], 2000);
    final imageUri = Uri.tryParse(image);
    final price = raw['price'];
    items.add(
      ShareItem(
        name: name,
        brand: clip(raw['brand'], 100),
        url: url,
        image: imageUri != null && imageUri.scheme == 'https' && publicHost(imageUri.host) ? image : null,
        price: price is num && price >= 0 && price.isFinite ? price.toDouble() : null,
        currency: price is num ? clip(raw['currency'], 3).toUpperCase() : '',
      ),
    );
  }
  if (items.isEmpty) throw const FormatException('This wish list has no items Vastra can open.');
  return SharedList(
    name: clip(data['name'], 60).isEmpty ? 'Shared list' : clip(data['name'], 60),
    message: clip(data['message'], 300),
    items: items,
  );
}

/// A link-only catalog entry for a shared item. The owner can refresh it later.
Product productFromShared(ShareItem i, {Categorizer? categorizer}) {
  final kind = (categorizer ?? Categorizer()).classify(name: i.name, sourceCategory: '', description: '');
  return Product(
    id: const Uuid().v4(),
    name: i.name,
    brand: i.brand,
    category: kind.category,
    productType: kind.type,
    description: '',
    images: [?i.image],
    offers: [
      Offer(
        seller: Uri.parse(i.url).host,
        url: i.url,
        price: i.price,
        currency: i.currency.isEmpty ? null : i.currency,
      ),
    ],
    sourceUrl: i.url,
    checkedAt: DateTime.now().toUtc().toIso8601String(),
    sample: false,
    extraction: 'link',
  );
}

/// A name safe to use in a file name.
String fileSlug(String name) {
  final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'list' : (slug.length > 40 ? slug.substring(0, 40) : slug);
}

String _h(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// The self-contained page: no outside scripts or fonts, and a content
/// security policy that allows only this page's own script and HTTPS images.
/// Item text is written as escaped HTML; the script only toggles classes.
String sharePage(SharedList list) {
  final b = StringBuffer();
  for (final (n, i) in list.items.indexed) {
    final price = i.price == null
        ? ''
        : '${i.currency.isEmpty ? '' : '${_h(i.currency)} '}${i.price!.toStringAsFixed(2)}';
    b.write(
      '<li data-n="${n + 1}">'
      '${i.image == null ? '<div class="ph"></div>' : '<img src="${_h(i.image!)}" alt="" loading="lazy" referrerpolicy="no-referrer">'}'
      '<div class="t"><b>${_h(i.name)}</b>'
      '${i.brand.isEmpty ? '' : '<span>${_h(i.brand)}</span>'}'
      '${price.isEmpty ? '' : '<span>$price</span>'}'
      '<a href="${_h(i.url)}" rel="noopener noreferrer nofollow" target="_blank">View in the shop</a>'
      '<button type="button" class="claim">I\'ll buy this</button>'
      '<em class="taken">Someone is already getting this.</em></div></li>',
    );
  }
  final values = {
    'id': list.id,
    'title': _h(list.name),
    'message': list.message.isEmpty ? '' : '<p>${_h(list.message)}</p>',
    'items': b.toString(),
  };
  // One pass, so text inside an item can never be mistaken for a placeholder.
  return _page.replaceAllMapped(RegExp(r'\{\{(id|title|message|items)\}\}'), (m) => values[m[1]]!);
}

/// A claim someone pastes into a chat: which items of which list they will buy.
String claimCode(String listId, Iterable<int> numbers) =>
    'vastra-claim:$listId:${(numbers.toList()..sort()).join(',')}';

const _page = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer">
<title>{{title}}</title>
<style>
:root{--bg:#faf6f0;--ink:#2b2420;--soft:#6d6259;--line:#d8cdbf;--accent:#a8582c}
@media (prefers-color-scheme:dark){:root{--bg:#1f1b18;--ink:#f1e9df;--soft:#b3a699;--line:#40382f;--accent:#e08a5a}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,sans-serif}
main{max-width:720px;margin:0 auto;padding:24px 16px 64px}
h1{margin:0 0 4px;font-size:28px}
ul{list-style:none;padding:0;margin:24px 0}
li{display:flex;gap:16px;padding:16px 0;border-top:1px solid var(--line)}
img,.ph{width:96px;height:120px;object-fit:cover;background:var(--line);flex:none}
.t{display:flex;flex-direction:column;gap:4px;align-items:flex-start}
.t span{color:var(--soft);font-size:14px}
a{color:var(--accent)}
button{font:inherit;padding:6px 12px;border:1.5px solid var(--accent);background:transparent;color:var(--accent);border-radius:4px;cursor:pointer}
li.mine button{background:var(--accent);color:var(--bg)}
.taken{display:none;color:var(--soft);font-size:14px}
li.other .taken{display:block}li.other button{display:none}li.other{opacity:.65}
textarea{width:100%;box-sizing:border-box;min-height:64px;font:14px monospace;background:transparent;color:var(--ink);border:1px solid var(--line)}
.note{color:var(--soft);font-size:14px}
</style></head>
<body data-list="{{id}}"><main>
<h1>{{title}}</h1>{{message}}
<p class="note">A wish list made with Vastra. You do not need an account. To avoid doubled gifts, tap <b>I'll buy this</b> on what you will get, then send your code to the other gift givers (not to the list's owner, if it is a surprise). Paste codes you receive below.</p>
<ul>{{items}}</ul>
<h2>Your code</h2>
<textarea id="mine" readonly aria-label="Your code to send to the other gift givers"></textarea>
<h2>Codes from others</h2>
<textarea id="others" placeholder="Paste codes here, one per line" aria-label="Codes from other gift givers"></textarea>
<p class="note">Your choices stay in this browser. Nothing is sent anywhere.</p>
</main>
<script>
(function(){
var id=document.body.getAttribute('data-list'),key='vastra-list-'+id,mine=[],items=document.querySelectorAll('li');
try{mine=JSON.parse(localStorage.getItem(key)||'[]').filter(Number.isInteger)}catch(e){}
var o=document.getElementById('others'),m=document.getElementById('mine');
function others(){var s={};o.value.split(/\n/).forEach(function(l){
 var p=l.trim().match(/^vastra-claim:([0-9a-f]{8}):([0-9,]*)$/);
 if(p&&p[1]===id)p[2].split(',').forEach(function(n){if(n)s[+n]=1})});return s}
function draw(){var t=others();
 items.forEach(function(li){var n=+li.getAttribute('data-n'),me=mine.indexOf(n)>=0;
  li.className=me?'mine':(t[n]?'other':'');
  li.querySelector('button').textContent=me?"You're getting this (tap to undo)":"I'll buy this"});
 m.value=mine.length?'vastra-claim:'+id+':'+mine.slice().sort(function(a,b){return a-b}).join(','):'';
 try{localStorage.setItem(key,JSON.stringify(mine))}catch(e){}}
items.forEach(function(li){li.querySelector('button').addEventListener('click',function(){
 var n=+li.getAttribute('data-n'),i=mine.indexOf(n);if(i>=0)mine.splice(i,1);else mine.push(n);draw()})});
o.addEventListener('input',draw);m.addEventListener('focus',function(){m.select()});
draw();
})();
</script></body></html>''';
