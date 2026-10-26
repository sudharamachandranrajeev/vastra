import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'data/catalog_data.dart';
import 'data/catalog_repository.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Inter', 'Lora']) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  await start();
}

Future<void> start() async {
  try {
    final data = await CatalogData.load();
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = sqlite3.open(path.join(directory.path, 'vastra.sqlite'));
    late final CatalogRepository repository;
    try {
      repository = CatalogRepository(database);
    } on Object {
      database.close();
      rethrow;
    }
    debugPrint('Vastra catalog opened');
    runApp(VastraApp(data: data, repository: repository));
  } on Object catch (error) {
    debugPrint('Vastra startup failed: $error');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 20),
                    const Text('Vastra could not open your catalog'),
                    const SizedBox(height: 12),
                    Text('$error'),
                    const Text('Your data has not been deleted or reset.'),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: start, child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
