import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/product.dart';

class CatalogData {
  CatalogData({
    required this.samples,
    required this.sellers,
    required this.categories,
    required this.retailers,
  });
  final List<Product> samples;
  final List<Map<String, dynamic>> sellers;
  final List<String> categories, retailers;
  static Future<CatalogData> load() async {
    Future<dynamic> read(String name) async =>
        jsonDecode(await rootBundle.loadString('assets/data/$name.json'));
    return CatalogData(
      samples: (await read('products') as List)
          .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      sellers: (await read('sellers') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      categories: List<String>.from(await read('categories') as List),
      retailers: List<String>.from(await read('retailers') as List),
    );
  }
}
