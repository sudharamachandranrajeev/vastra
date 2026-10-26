import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/ui/app.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('native navigation, search and local collection at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CatalogRepository.memory();
      addTearDown(repo.close);
      final data = await tester.runAsync(CatalogData.load);
      expect(data, isNotNull);
      await tester.pumpWidget(VastraApp(data: data!, repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('A world of good finds.\nAn edit that’s you.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'tailored cotton white');
      await tester.pumpAndSettle();
      final save = find.byTooltip('Save The tailored cotton shirt');
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find
            .descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.readAll().single.collection, 'My edit');
      await tester.tap(find.text('Collections').last);
      await tester.pumpAndSettle();
      expect(find.text('The tailored cotton shirt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
