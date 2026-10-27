import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'data/catalog_data.dart';
import 'data/catalog_repository.dart';
import 'data/diagnostics.dart';
import 'data/settings_store.dart';
import 'data/share_intake.dart';
import 'data/updater.dart';
import 'ui/app.dart';
import 'ui/feedback.dart';
import 'ui/maintenance.dart';
import 'ui/paper.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Inter', 'Lora']) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  await start(ShareIntake(arguments));
}

Future<void> start(ShareIntake intake) async {
  var diagnostics = Diagnostics();
  try {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    diagnostics = Diagnostics(File(path.join(directory.path, 'diagnostics.log')));
    _recordErrors(diagnostics);
    final data = await CatalogData.load();
    final settings = SettingsStore(File(path.join(directory.path, 'settings.json')));
    final database = sqlite3.open(path.join(directory.path, 'vastra.sqlite'));
    late final CatalogRepository repository;
    try {
      repository = CatalogRepository(database);
    } on Object {
      database.close();
      rethrow;
    }
    debugPrint('Vastra catalog opened');
    runApp(
      VastraApp(
        data: data,
        repository: repository,
        intake: intake,
        feedback: UiFeedback(settings: settings),
        diagnostics: diagnostics,
        updates: UpdateService(
          settings: settings,
          workDirectory: await getTemporaryDirectory(),
          backupDirectory: Directory(path.join(directory.path, 'backups')),
        ),
      ),
    );
  } on Object catch (error, stack) {
    debugPrint('Vastra startup failed: $error');
    diagnostics.record(error, stack);
    runApp(
      MaterialApp(
        theme: paperTheme(),
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
                    CopperButton(label: 'Try again', onPressed: () => start(intake)),
                    const SizedBox(height: 12),
                    PaperButton(
                      label: 'Report this problem',
                      icon: Icons.bug_report_outlined,
                      onPressed: () => openExternal(
                        issueLink(
                          'Vastra could not open its catalog',
                          bugReport(summary: redact('$error'), steps: 'Opened Vastra.', errors: diagnostics.recent),
                        ),
                      ),
                    ),
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

/// Keeps uncaught errors for bug reports, while still showing them as usual.
void _recordErrors(Diagnostics diagnostics) {
  FlutterError.onError = (details) {
    diagnostics.record(details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.record(error, stack);
    debugPrint('Vastra error: $error');
    return true;
  };
}
