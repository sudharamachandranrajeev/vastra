# Vastra native

Standalone Flutter application for Android, Windows and Linux. No Brahma dependency or account is required. Native catalogs are local; they do not currently sync with the hosted web app.

From this directory:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test --concurrency=2 --timeout 60s
flutter run -d linux
```

Build the platform available on your host:

```sh
flutter build linux --release
flutter build windows --release
flutter build apk --release
```

Signed Android builds require `VASTRA_KEYSTORE`, `VASTRA_KEYSTORE_PASSWORD`, `VASTRA_KEY_ALIAS`, and `VASTRA_KEY_PASSWORD`. Only for a local development APK, `VASTRA_ALLOW_DEBUG_SIGNING=true` explicitly enables debug-key signing. Published builds use the persistent release key.

See [native development and packaging](../docs/NATIVE.md) for data locations, signing, release builds and installer behavior.
