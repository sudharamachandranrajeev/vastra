# Changelog

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

## 0.2.0

- Standalone Flutter applications for Android, Windows and Linux, with an offline inspiration catalog.
- Local SQLite storage for imported products and named collections; no Brahma account or sign-in required.
- Direct product-link extraction, original-currency offers, source evidence, refreshes, comparisons, and curated seller contacts.
- Persistent Android release signing, per-user Windows installer, Linux launcher installer, and checksum-pinned Arch package generation.
- Shared sample catalog, seller directory, merchant policy, and extraction fixtures across web and native clients.
- README styling aligned with Anveshana and Vidya.

## 0.1.0

- Initial web discovery app, authenticated catalog, collections, comparisons and merchant-link extraction.
