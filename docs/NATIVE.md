# Native development and packaging

Vastra's standalone Flutter client lives in `native/`. It runs on Android, Windows and Linux,
with standard GTK launcher integration on Arch and Omarchy. There is no Brahma dependency,
account requirement, web-view shell, or connection to the hosted catalog.

## Ownership

- `native/lib/domain/`: products, source offers, direct bounded merchant retrieval and extraction.
- `native/lib/data/`: asset loading and local SQLite persistence.
- `native/lib/ui/`: responsive native discovery, collections, seller directory and comparisons.
- `native/lib/domain/`: categorization, similar-find suggestions and catalog export.
- `native/assets/data/`: the canonical sample products, categories, seller directory and the
  web importer's merchant host allowlist. The web client reads these same tracked JSON files.
- `tests/fixtures/extraction.json`: shared normalization expectations exercised by TypeScript and Dart.
- `native/test/`: isolated persistence, URL policy, extraction, fixture and interface checks.

The native importer uses the Dart HTML parser; the hosted importer uses the Workers HTML parser.
The two implementations target the same product data contract. Common fixtures check their
behavior without introducing an embedded JavaScript runtime into the native packages.

## Local data

`path_provider` selects the app's support directory. The database is `vastra.sqlite` inside it:

- Linux: normally `~/.local/share/io.github.sudharamachandranrajeev.vastra/vastra.sqlite`.
- Windows: the Vastra application-support directory under `%APPDATA%`.
- Android: the application's private support directory.

Imported products, their source URLs, refreshed documents and saved collection names are stored
in SQLite. Samples are only persisted when saved. Refreshes update an existing source in a
transaction, keeping its ID and collection. Writes use parameter binding, unique source URLs and
a busy timeout. A newer unsupported database version fails closed rather than resetting data.

There is no database encryption or automatic backup in this version. On desktop, close Vastra
before copying its database for a manual backup. Uninstalling the desktop program does not remove
the database; Android uninstall normally does remove private app data. Web and native catalogs
are separate.

## Price and stock watching

Every import and refresh records one row per offer, and one per identifiable variant (size and
colour, or SKU), in `price_points`. A refresh the store blocked records a failed check instead
and keeps the earlier details. A watch (`watches`) covers a whole item or one variant, price
drops (any, percent, or target price) and/or back-in-stock. Rules live in
`lib/domain/watching.dart`:

- An alert comes only from a successful check compared with the previous successful check from
  the same seller and variant. A different currency, an unknown earlier stock state, or a price
  drop on a sold-out item never alerts.
- Alerts are queued in `alerts`. Ones marked "Tell me at once" are shown right away, up to five,
  then a summary. The rest go out as one digest notification at most every 20 hours. With alerts
  off, queued alerts are dropped, not saved up.
- Offers are marked stale after 7 days without a successful check, or when the last check was
  blocked.

Checks are opt-in. Android runs a WorkManager job hourly (network connected, battery not low),
which checks only what is due: hourly for "at once" watches and daily otherwise. Desktop
checks on a 15-minute timer while Vastra is open. Requests to the same host are spaced
3–6 seconds apart. Notifications use `flutter_local_notifications`, and there is no other
notification channel. The new tables are additive, so the catalog stays at `user_version` 1 and
older versions can still open it after a rollback. Restore brings history and watches only for
the finds it adds.

## Size and fit

`fits` keeps one record per item: brand, size, kept or returned, fit (small, right or large) and
a free note. `suggestSize` in `lib/domain/fit.dart` compares brands without case or punctuation.
It scores each size: +2 if kept and fit right, +1 if kept but small or large, -1 if returned. It
suggests the top size only when that score is positive, and lists the records behind it. The
importer saves the first page table marked as a size chart or guide (by id, class, aria-label or
caption), or one whose header names a size, at up to 25 rows and 12 columns, as
`Product.sizeChart`. Fit data is never sent anywhere and is not part of any export. Backups and
restores include it.

## Import policy

The native apps accept a link from any public store. The link can arrive from the Android share
sheet or text-selection menu (`ACTION_SEND` and `PROCESS_TEXT`), from desktop command-line
arguments, from a link copied to the clipboard (desktop only), or by pasting. Vastra takes the
first link in shared text, upgrades `http` to HTTPS and removes tracking parameters. It refuses
embedded credentials, nonstandard ports, IP literals, private and local names. Every redirect is
checked again, so short links resolve to the store page. Imports have a 20-second deadline, a
4 MB response limit and at most six followed redirects.

Structured data (schema.org JSON-LD) is preferred over page metadata. Vastra captures the
following details:

- Name, brand, description and images.
- Offers, including aggregate offers.
- Variants with SKU, GTIN, size, colour, price and stock.
- Identifiers: GTIN, MPN and SKU.
- Material, pattern, condition, audience, ratings, keywords and breadcrumbs.

Unknown fields remain unknown. When a store blocks reading or the page has no product data, the
link is still saved. Its name comes from page metadata, the shared text or the URL slug, and it
can be refreshed later. A refresh never replaces richer saved details with a link-only result.

Native apps fetch stores directly from the device. A store's access policy can differ from the
hosted Worker's access. The app reports blocked or unusable pages instead of bypassing controls.
The hosted web app keeps its retailer host allowlist, because it fetches on a shared server.

## Categories, suggestions and export

`categorizer.dart` files each find under a category and a type. The rules run in this order:

1. Keyword rules on the name. The last matching word wins, because it is usually the head noun.
2. The store's own category or breadcrumb.
3. A naive Bayes model trained on the user's corrections.
4. The description.

Each type maps to a Google product taxonomy path. `recommender.dart` ranks similar finds by
TF-IDF cosine similarity, boosted for shared category, type, colour, brand and price band. This
is the approach used by Lucene MoreLikeThis. Everything runs on the device.

`catalog_export.dart` writes the following files:

- A Shopify product CSV with draft products, one row per variant and image.
- A tab-separated product feed with Google product data attributes. Google Merchant Center, Meta,
  Pinterest and TikTok catalogs accept this feed.
- A schema.org `ItemList` JSON file that keeps every captured detail.

## Updates, rollback and bug reports

`updater.dart` reads the GitHub releases API for this repository. By default it does this when
Vastra starts, and Settings can turn the check off. Only `v<major>.<minor>.<patch>` tags count.
Only download links under this repository's release files are used. A package installs only if
its SHA-256 matches the release's `SHA256SUMS.txt`. Before any version change, Vastra copies the
catalog to `backups/` in its support directory and keeps the newest five copies.

How each install type changes version:

- Android: the verified APK goes to the system installer through a `FileProvider` limited to
  the app's `cache/updates/` folder. Android asks the user to allow installs from Vastra once,
  and to confirm each install. Android does not install an older version over a newer one. A
  rollback therefore guides the user through these steps:
  1. Back up the catalog to a file.
  2. Save the verified older APK.
  3. Uninstall Vastra, then install the saved APK.
  4. Restore the backup.
- Windows installer: Vastra runs the verified setup with `/SILENT /relaunch=1` and closes. Inno
  Setup replaces the program and reopens it.
- Linux, installed with `install.sh`: Vastra unpacks the verified archive and runs its
  `install.sh` for the same prefix. It then restarts.
- Portable Windows folders and the Arch package are managed outside Vastra. For these, Vastra
  opens the release page instead of replacing files.

Settings can back up the catalog to a file and restore one. A restore adds the finds that are
missing and never overwrites finds already present. Backups from newer catalog versions are
refused.

Uncaught errors are kept in `diagnostics.log`, which holds the newest 80 lines. Link paths and
the home folder are removed from it. "Report a problem" opens a prefilled GitHub issue in the
browser. The user can preview the text and leave the errors out. Vastra sends nothing itself.

## Interface and sound

`paper.dart` holds the neo-skeuomorphic paper design system: tokens, raised and pressed
surfaces, copper buttons, folder tabs, envelope dialogs and staggered arrivals. `feedback.dart`
plays very quiet interface sounds with light haptics. Settings can turn either off. The sounds
are generated by `tool/make_sounds.py` and bundled in `assets/sounds/`.

## Builds

From `native/`:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test --concurrency=2 --timeout 60s
flutter build linux --release       # on Linux
flutter build windows --release     # on Windows
flutter build apk --release         # requires release signing environment
```

From the repository root, after the Linux build:

```sh
scripts/package-linux.sh 0.3.0
scripts/install-linux.sh
scripts/install-linux.sh --uninstall
```

For an isolated installer check, use `--prefix /absolute/test/prefix`. The installer refuses to
replace unmanaged directories and launchers, stages upgrades before swapping the program, and
never touches the catalog. It writes only standard application launcher/icon entries; it does
not modify Hyprland, Omarchy, terminal, theme, or system settings.

The release job builds Linux on Ubuntu 22.04 for a portable glibc baseline, then smoke-tests the
archive on Ubuntu and Arch. Arch packaging uses the exact archive's SHA-256; the generated
`PKGBUILD` and installable `.pkg.tar.zst` are release artifacts. No AUR package is published.
Windows includes a portable ZIP and a per-user Inno Setup installer with bundled VC++ runtime DLLs.

## Android signing

The application ID is `io.github.sudharamachandranrajeev.vastra`. Release signing uses:

- `VASTRA_KEYSTORE`: path to the dedicated PKCS#12 key file.
- `VASTRA_KEYSTORE_PASSWORD`, `VASTRA_KEY_ALIAS`, `VASTRA_KEY_PASSWORD`.
- GitHub Actions additionally uses `VASTRA_KEYSTORE_BASE64` to restore that key in the runner's
  temporary directory. No key or password is tracked by Git.

The initial dedicated key and its private settings are kept outside this repository at
`../vastra-android-keystore/`. Back up that directory securely: the same signing identity is
needed to install future updates without uninstalling the app. GitHub secrets contain the CI
copy; their plaintext values cannot be downloaded later through GitHub.

A local testing-only APK may explicitly set `VASTRA_ALLOW_DEBUG_SIGNING=true` to use the SDK debug
key. Public release jobs require the persistent signing secrets and never silently fall back.

## CI and releases

`native.yml` analyzes and tests every push and pull request. `release.yml` builds signed Android,
Windows installer/portable and Linux packages; it then smoke-tests Android startup, Windows
install/start/uninstall, Ubuntu and Arch startup, and Linux install/uninstall. A manual run saves
artifacts. A matching `v<pubspec-version>` tag publishes a prerelease only after those jobs pass,
including the Arch package build. Downloads include SHA-256 checksums.

Desktop screenshots can be reproduced with:

```sh
cd native
VASTRA_SHOTS=../docs/screenshots flutter test test/screenshots_test.dart --timeout 60s
```

## Fonts and sample photos

Inter and Lora are bundled under SIL OFL; their notices are in `assets/fonts/`. Sample photographs
are bundled for offline rendering under the Unsplash license, with their source URLs preserved
in the shared sample data. Imported merchant images are referenced remotely and are not copied
into Vastra's sample assets.
