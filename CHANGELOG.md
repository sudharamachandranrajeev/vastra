# Changelog

## 0.10.0

- Shop in Vastra: search Amazon, eBay, Google Shopping, Etsy or Pinterest, return to a shop already in
  your catalog, or go to any shop's address, all in Vastra's own browser. Choose which Amazon and eBay
  country to use. On Android the browser opens inside the app; on Windows and Linux it opens in its
  own window.
- Sign in to shops in that browser, so you see your own prices, member prices and country. The sign-in
  goes to the shop and stays in Vastra's browser on this device. Vastra never sees your password.
  **Sign out of shops** in Settings forgets every shop sign-in and cookie.
- **Save to Vastra** on any product page reads what the page is showing: the shop's product data when
  it has some, otherwise the name, price, brand and photos on the screen. Select the product's name
  first if Vastra picks the wrong one. Form fields are removed before reading, so typed or saved
  personal details are never read. Saving the same page again updates the price.
- From a screenshot: pick a screenshot of a product (from social media, a chat or a shop) and Vastra
  reads its words, price and links on the device, then searches the shops for them. Android reads text
  with Google's on-device recognizer, bundled with the app. Windows and Linux use Tesseract if it is
  installed. No image is sent anywhere.
- **Open in Vastra's browser** on any find, and **Find similar elsewhere** now opens in it too.
- Linux now needs WebKitGTK 4.1 (`webkit2gtk-4.1`). Windows uses the WebView2 runtime, which Windows 10
  and 11 already include.
- The Android app is about 33 MB larger, because the text recognizer is included so it works without
  Google Play services or a download.

## 0.9.0

- Search by photo: pick a photo of something you like and Vastra lists the finds and samples with the
  closest colours and pattern. **Find this look** on any item does the same from its photo. Matching
  happens on your device; the photo is not saved or sent anywhere. It compares colour and pattern,
  not shape or cut, and leaves out weak matches.
- Suggested details: when a shop leaves out the colour, material or pattern, Vastra suggests them from
  the item's own words and, if you ask, its photo. Each suggestion says where it came from. Use it,
  edit it, or mark it "Not right"; nothing changes until you choose, and a refresh keeps what you
  chose unless the shop now states it.
- No AI service, account or cost: everything is worked out on the device.

## 0.8.0

- Encrypted backups: choose a passphrase and Vastra saves a `.vstrbk` file (AES-256-GCM, key from
  Argon2id). A wrong passphrase or a changed file is refused. Unencrypted backups are still possible
  if you choose them, and old ones restore as before.
- Sync with your own server: one encrypted file in a WebDAV folder you run, such as Nextcloud. It is
  encrypted on your device, so the server cannot read it. The password and passphrase are never saved.
- Restore and sync now also add price history, wear days, outfits, plans and packing lists to finds you
  already have, and recognise the same store page saved on two devices. They still never delete or
  overwrite anything.

## 0.7.0

- Share a collection as a wish list page: one file that opens in any browser, with no account. It shows
  names, photos, shop links and, if you choose, prices.
- Gift reservation without a server: gift givers tap "I'll buy this" and swap short codes, so gifts are
  not doubled and the owner does not see who chose what.
- Wish list files that another Vastra opens as a collection ("Open a shared list").
- Private collections: tick one and its finds are left out of every export and shared list.
- Shared files are checked on opening: only public HTTPS links and images are kept.

## 0.6.0

- New Wardrobe tab. Mark finds as owned with the price paid, and log the days you wore them.
- Statistics: items owned, total paid per currency, most worn, best cost per wear, never worn.
- Outfit boards and moodboards built from items you own or only want.
- A 14-day planner. Move an outfit to another day, mark what you wore, and ask for a reminder that
  morning. Reminders are off until you turn on **Outfit reminders** in Settings.
- Packing lists, by hand, from an outfit, or from the outfits planned between two dates.
- No item limit, no ads, no account. Backups carry the wardrobe and restoring never duplicates
  outfits or lists.

## 0.5.0

- Size and fit: after buying, record the size, whether you kept it, and how it fit, plus an optional
  "fits me" note.
- Your size per brand: any item from a brand you have bought before shows the size your own history
  points to, with the records behind it.
- The store's size chart is captured when the page publishes one and shown on the item.
- Sizes and fit notes stay on the device. Exports leave them out, and backups keep them.

## 0.4.0

- Watch any find for price drops and back-in-stock, for the whole item or one size and colour.
  Thresholds: any drop, a percentage, or a target price.
- Alerts arrive as one daily digest, or straight away for items marked "Tell me at once". There is no
  other notification channel, and one switch turns every alert off.
- Alerts come only from a check that just succeeded, and name the old and new price, the store and
  when it checked. A blocked check never alerts.
- Price history for every find, with low, high and current prices, and a warning when prices are
  more than 7 days old or the store blocked the last check.
- Optional automatic checks: in the background on Android, while open on Windows and Linux.
  "Watched only" filter in My catalog.
- Backups carry price history and watches. Older versions still open the catalog after a rollback.

## 0.3.0

- Native apps accept product links from any public store. Links can arrive from the Android share
  sheet, the text-selection menu, desktop arguments, a copied link or a paste. Short links and
  tracking parameters are handled.
- Blocked and non-product pages still save the find from the shared text, page metadata or URL.
- Richer capture: variants, SKU, GTIN, MPN, pattern, condition, audience, ratings, keywords and
  breadcrumbs.
- Automatic category and type, with a Google product taxonomy path, learned from corrections.
- "More like this" and "Picked for you" suggestions use on-device TF-IDF similarity.
- Export to a Shopify product CSV, a Google, Meta, Pinterest and TikTok product feed, or
  schema.org JSON.
- Neo-skeuomorphic paper redesign with fluid transitions, plus optional quiet sounds and haptics.
- Phased feature plan from user research in `docs/ROADMAP.md`.
- In-app updates from GitHub releases. Vastra checks at startup (can be turned off) and verifies
  every package against the release's SHA-256 checksums before installing it.
- Roll back to any published version from Settings. The catalog is copied before every version
  change.
- Catalog backup and restore. Restoring adds missing finds and keeps the ones already present.
- Bug reporter that opens a prefilled GitHub issue. Recent errors are optional and redacted.
- Linux builds and the Arch package declare GStreamer, which the interface sounds need.

## 0.2.0

- Standalone Flutter applications for Android, Windows and Linux, with an offline inspiration catalog.
- Local SQLite storage for imported products and named collections; no Brahma account or sign-in required.
- Direct product-link extraction, original-currency offers, source evidence, refreshes, comparisons, and curated seller contacts.
- Persistent Android release signing, per-user Windows installer, Linux launcher installer, and checksum-pinned Arch package generation.
- Shared sample catalog, seller directory, merchant policy, and extraction fixtures across web and native clients.
- README styling aligned with Anveshana and Vidya.

## 0.1.0

- Initial web discovery app, authenticated catalog, collections, comparisons and merchant-link extraction.
