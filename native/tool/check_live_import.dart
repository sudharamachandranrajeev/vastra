import 'dart:convert';
import 'dart:io';

import 'package:vastra/domain/product_importer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_live_import.dart <product link or shared text>');
    exitCode = 2;
    return;
  }
  final product = await ProductImporter().fetch(arguments.single);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(product.toJson()));
}
