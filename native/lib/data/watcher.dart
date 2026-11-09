import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/product_importer.dart';
import '../domain/watching.dart';
import 'catalog_repository.dart';
import 'settings_store.dart';

/// Shows a system notification. Tests pass a recorder instead.
typedef Notify = Future<void> Function(int id, String title, String body);

/// Settings keys. Alerts are on by default; background checks are off until
/// the owner turns them on.
const alertsKey = 'watch.alerts', backgroundKey = 'watch.background', _digestKey = 'watch.lastDigest';

/// How often a watched item is checked: hourly when the owner asked to hear
/// at once, otherwise daily.
Duration checkInterval(Watch w) => w.immediate ? const Duration(minutes: 55) : const Duration(hours: 23);

/// Refreshes watched items and delivers their alerts. The app uses it while
/// open, and the Android background job uses it with its own connection.
class WatchService {
  WatchService({
    required this.repository,
    required this.settings,
    required this.importer,
    this.notify,
    Random? random,
  }) : _random = random ?? Random();
  final CatalogRepository repository;
  final SettingsStore settings;

  /// Made per run, so the app's learned categories apply to refreshes too.
  final ProductImporter Function() importer;
  final Notify? notify;
  final Random _random;
  bool _running = false;

  bool get alertsOn => settings.get<bool>(alertsKey) ?? true;
  bool get backgroundOn => settings.get<bool>(backgroundKey) ?? false;

  /// Checks every watched item that is due, or all of them when [all] is
  /// true, one at a time and a few seconds apart on the same store. Returns
  /// how many were checked.
  Future<int> checkDue({bool all = false, Duration spacing = const Duration(seconds: 3)}) async {
    if (_running) return 0;
    _running = true;
    try {
      final now = DateTime.now().toUtc();
      final products = {for (final e in repository.readAll()) e.product.id: e.product};
      var checked = 0;
      String? lastHost;
      final fetcher = importer();
      for (final watch in repository.watches()) {
        final product = products[watch.productId];
        if (product == null || product.sample) continue;
        final last = repository.lastChecked(product.id);
        if (!all && last != null && now.difference(last) < checkInterval(watch)) continue;
        final host = Uri.tryParse(product.sourceUrl)?.host;
        if (host != null && host == lastHost) {
          await Future<void>.delayed(spacing + spacing * _random.nextDouble());
        }
        lastHost = host;
        try {
          repository.importProduct(await fetcher.fetch(product.sourceUrl));
          checked++;
        } on Object catch (error) {
          // One unreachable store never stops the other checks.
          debugPrint('Vastra watch check failed: $error');
        }
      }
      await deliver();
      return checked;
    } finally {
      _running = false;
    }
  }

  /// Sends what is waiting: alerts marked "at once" right away, the rest as
  /// one digest at most once a day. With alerts off nothing is sent and
  /// nothing piles up for later.
  Future<void> deliver({DateTime? at}) async {
    final now = (at ?? DateTime.now()).toUtc();
    final pending = repository.pendingAlerts();
    if (pending.isEmpty) return;
    if (!alertsOn || notify == null) {
      if (!alertsOn) repository.markDelivered(pending.map((p) => p.$1), now);
      return;
    }
    final immediate = pending.where((p) => p.$2.immediate).toList();
    for (final (id, alert) in immediate.take(5)) {
      await notify!(id, alert.title, alert.body);
    }
    if (immediate.length > 5) {
      await notify!(
        immediate[5].$1,
        '${immediate.length - 5} more changes on items you watch',
        'Open Vastra to see them.',
      );
    }
    repository.markDelivered(immediate.map((p) => p.$1), now);

    final digest = pending.where((p) => !p.$2.immediate).toList();
    final last = DateTime.tryParse(settings.get<String>(_digestKey) ?? '');
    if (digest.isEmpty || (last != null && now.difference(last) < const Duration(hours: 20))) return;
    final lines = digest.map((p) => '${p.$2.title}. ${p.$2.body}').toList();
    await notify!(
      0,
      digest.length == 1 ? digest.first.$2.title : '${digest.length} changes on items you watch',
      [...lines.take(4), if (lines.length > 4) 'And ${lines.length - 4} more in Vastra.'].join('\n'),
    );
    repository.markDelivered(digest.map((p) => p.$1), now);
    settings.set(_digestKey, now.toIso8601String());
  }
}

final _notifications = FlutterLocalNotificationsPlugin();
bool _notificationsReady = false;

/// Shows notifications on Android, Windows and Linux.
Future<void> systemNotify(int id, String title, String body) async {
  if (!_notificationsReady) {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open Vastra'),
        windows: WindowsInitializationSettings(
          appName: 'Vastra',
          appUserModelId: 'SudharamachandranRajeev.Vastra',
          guid: '6c0f1e1b-4f5e-4a0c-9f3e-6a1f0d8b7c21',
        ),
      ),
    );
    _notificationsReady = true;
  }
  await _notifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'watch',
        'Price and stock alerts',
        channelDescription: 'Only the items you chose to watch.',
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
}

/// Asks Android 13+ for permission to notify. Other platforms need none.
Future<bool> requestNotifyPermission() async {
  if (!Platform.isAndroid) return true;
  final android = _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? true;
}

const _task = 'vastra-watch';

/// Turns the Android background job on or off. Desktop checks run on a timer
/// while Vastra is open instead, which the app owns.
Future<void> scheduleBackground(bool enabled) async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(backgroundDispatcher);
  if (!enabled) {
    await Workmanager().cancelByUniqueName(_task);
    return;
  }
  await Workmanager().registerPeriodicTask(
    _task,
    _task,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// The Android background job: opens the catalog, checks what is due and
/// delivers alerts, then closes everything again.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final directory = await getApplicationSupportDirectory();
    final settings = SettingsStore(File(path.join(directory.path, 'settings.json')));
    if (settings.get<bool>(backgroundKey) != true) return true;
    final database = sqlite3.open(path.join(directory.path, 'vastra.sqlite'));
    try {
      final service = WatchService(
        repository: CatalogRepository(database),
        settings: settings,
        importer: ProductImporter.new,
        notify: systemNotify,
      );
      await service.checkDue();
    } on Object catch (error) {
      debugPrint('Vastra background check failed: $error');
    } finally {
      database.close();
    }
    return true;
  });
}
