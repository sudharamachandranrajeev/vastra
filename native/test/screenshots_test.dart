import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/ui/app.dart';

void main() {
  final output = Platform.environment['VASTRA_SHOTS'];
  for (final size in [const Size(1440, 1120), const Size(390, 844)]) {
    testWidgets('render native ${size.width > 800 ? 'desktop' : 'phone'} screenshot', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = await tester.runAsync(() async {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        for (final family in ['Inter', 'Lora']) {
          await (FontLoader(
                family,
              )..addFont(rootBundle.load('assets/fonts/${family == 'Inter' ? 'Inter-Regular' : 'Lora'}.ttf')))
              .load();
        }
        return CatalogData.load();
      });
      final repo = CatalogRepository.memory();
      addTearDown(repo.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: VastraApp(data: data!, repository: repo),
        ),
      );
      await tester.runAsync(() async {
        for (final product in data.samples) {
          await precacheImage(
            AssetImage('assets/images/${product.id}.jpg'),
            tester.element(find.byType(Home)),
          );
        }
      });
      await tester.pumpAndSettle();
      if (size.width < 800) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -380));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(output!);
        await directory.create(recursive: true);
        await File('${directory.path}/native-${size.width > 800 ? 'desktop' : 'phone'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }, skip: output == null);
  }
}
