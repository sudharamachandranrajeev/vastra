import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../domain/look.dart';
import '../domain/product.dart';
import '../domain/product_importer.dart';
import 'catalog_repository.dart';

const _maxImageBytes = 2 * 1024 * 1024;
const _maxPixels = 40 * 1000 * 1000;
const _retryAfter = Duration(days: 7);

/// Reads a photo and describes its look. The photo is shrunk to 32 pixels
/// across first, and pictures too large to decode safely are refused.
Future<LookDescriptor> describeImage(Uint8List bytes) async {
  if (bytes.length > _maxImageBytes) throw const FormatException('That photo is larger than 2 MB.');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } on Object {
      throw const FormatException('That file is not a photo Vastra can read.');
    }
    if (descriptor.width * descriptor.height > _maxPixels) {
      throw const FormatException('That photo has too many pixels to read.');
    }
    final width = descriptor.width < 32 ? descriptor.width : 32;
    codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: (descriptor.height * width / descriptor.width).ceil().clamp(1, 96),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw const FormatException('That file is not a photo Vastra can read.');
    return describePixels(data.buffer.asUint8List(), image.width, image.height);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Works out and caches the look of catalog photos. Samples are read from the
/// app itself; an imported item's first photo is downloaded once from its
/// public HTTPS address and only its look is kept. No photo leaves the device.
class LookService {
  LookService(
    this.repository, {
    http.Client Function()? clientFactory,
    Future<Uint8List> Function(String asset)? loadAsset,
    Future<LookDescriptor> Function(Uint8List bytes)? describe,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _loadAsset = loadAsset ?? ((a) async => (await rootBundle.load(a)).buffer.asUint8List()),
       _describe = describe ?? describeImage;
  final CatalogRepository repository;
  final http.Client Function() _clientFactory;
  final Future<Uint8List> Function(String asset) _loadAsset;
  final Future<LookDescriptor> Function(Uint8List bytes) _describe;

  /// Where the item's look comes from, or null when it has no usable photo.
  static String? imageOf(Product p) {
    if (p.sample) return 'asset:assets/images/${p.id}.jpg';
    final first = p.images.firstOrNull;
    final uri = first == null ? null : Uri.tryParse(first);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || !publicHost(uri.host)) return null;
    return first;
  }

  /// Looks for [products], working out the missing ones one at a time.
  /// Photos that failed are tried again after a week.
  Future<Map<String, LookDescriptor>> prepare(
    List<Product> products, {
    void Function(int done, int total)? progress,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final cache = repository.looks();
    final out = <String, LookDescriptor>{};
    final todo = <(Product, String)>[];
    for (final p in products) {
      final image = imageOf(p);
      if (image == null) continue;
      final hit = cache[p.id];
      if (hit != null && hit.image == image) {
        if (hit.look != null) {
          out[p.id] = hit.look!;
          continue;
        }
        if (at.difference(hit.at) < _retryAfter) continue;
      }
      todo.add((p, image));
    }
    final client = _clientFactory();
    try {
      for (final (i, (p, image)) in todo.indexed) {
        progress?.call(i, todo.length);
        LookDescriptor? look;
        try {
          final bytes = image.startsWith('asset:')
              ? await _loadAsset(image.substring(6))
              : await _download(client, Uri.parse(image));
          look = await _describe(bytes);
        } on Object {
          look = null;
        }
        repository.setLook(p.id, image, look, at);
        if (look != null) out[p.id] = look;
      }
      progress?.call(todo.length, todo.length);
    } finally {
      client.close();
    }
    return out;
  }

  Future<Uint8List> _download(http.Client client, Uri source) async {
    var uri = source;
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll({
        'Accept': 'image/*',
        'User-Agent': 'Vastra/0.9 (+https://github.com/sudharamachandranrajeev/vastra)',
      });
      final response = await client.send(request).timeout(const Duration(seconds: 10));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final next = uri.resolve(response.headers['location'] ?? '');
        if (next.scheme != 'https' || next.userInfo.isNotEmpty || !publicHost(next.host)) {
          throw const FormatException('The photo moved to an address Vastra does not fetch.');
        }
        uri = next;
        continue;
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').toLowerCase().startsWith('image/') ||
          (response.contentLength ?? 0) > _maxImageBytes) {
        await response.stream.listen((_) {}).cancel();
        throw const FormatException('The store did not share this photo.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(const Duration(seconds: 10))) {
        if (bytes.length + chunk.length > _maxImageBytes) {
          throw const FormatException('That photo is larger than 2 MB.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    throw const FormatException('The photo redirected too many times.');
  }
}
