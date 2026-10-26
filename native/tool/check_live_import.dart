import 'dart:convert';
import 'dart:io';

import 'package:vastra/domain/product_importer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_live_import.dart <HTTPS product URL>');
    exitCode = 2;
    return;
  }
  final stores = List<String>.from(jsonDecode(File('assets/data/retailers.json').readAsStringSync()) as List);
  final product = await ProductImporter(stores).fetch(arguments.single);
  stdout.writeln(
    jsonEncode({
      'name': product.name,
      'category': product.category,
      'offers': product.offers.map((o) => o.toJson()).toList(),
    }),
  );
}
