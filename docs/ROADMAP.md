# Vastra implementation roadmap

Launch preference: **global coverage, preserving original store currencies**.

## Native platforms

Standalone Flutter clients for Android, Windows and Linux now use local SQLite catalogs, links shared from any app or store, named collections, refreshes and comparisons. Their data is separate from the authenticated hosted web catalog. Brahma integration is intentionally excluded by the owner’s preference. Native distribution includes Android signing, Windows installer/portable packages, Linux user installation and Arch packaging.

## Feature plan from user research

Researched October 2026 across shopping, universal-wishlist and digital-wardrobe apps. The most liked and most requested features are below, one phase at a time. Each phase ships on its own and leaves the app complete.

What users ask for most: adding items from any store with details filled in automatically, price-drop and back-in-stock alerts, confidence about size and fit, outfit planning and wardrobe statistics, wishlists shared without making others sign up, sync across devices, and privacy controls.

What users hate, which Vastra never does:

- Forced sign-in before browsing or saving.
- Notification floods. BEUC counted 12 notifications in one day from Shein's app.
- False urgency and countdowns.
- Adding items to a basket without asking (basket sneaking).
- Confirm-shaming, nagging pop-ups and pressure not to leave.
- Hidden costs revealed late.
- Subscription traps and ads.
- Unexplained personalisation.
- Automatic tags the user cannot correct, which is the most common complaint about wardrobe apps.

### Phase 0 — capture anything, keep everything (0.3.0)

- Share from any app or browser to Vastra on Android, including selected text. On desktop, open Vastra with a link or confirm a copied link.
- Import from any public store. Short links are followed and tracking parameters removed. A blocked store still saves the item from its link, so a share is never lost.
- Full details: variants, SKU, GTIN, MPN, gender, rating, the seller's breadcrumb, and every image.
- Automatic category and type. Corrections are always one tap away and teach the categorizer (naive Bayes, on device).
- "More like this" (TF-IDF cosine with facet boosts, on device) and searches of other stores for similar items.
- Export to Shopify CSV, a Google, Meta, Pinterest and TikTok product feed, or schema.org JSON.
- The tactile paper-and-copper redesign, with soft sounds and haptics that can be muted.

### Phase 1 — price and stock watching

- Price history recorded on every refresh.
- Optional background refresh.
- Opt-in price-drop and back-in-stock alerts, per item, sent as at most one daily digest.
- Warnings when an offer is stale.

Acceptance: an alert names the old and new price and their source, and turning alerts off is one tap.

### Phase 2 — size and fit confidence

- A private size profile per brand: what you bought, what you kept, how it fit.
- Size charts captured when stores publish them.
- A "fits me" note on each item.
- Suggestions explain their evidence, and size data never leaves the device.

### Phase 3 — wardrobe and outfits

- Mark items as owned.
- Outfit boards built from catalog items, plus moodboards.
- A calendar planner with optional reminders, and packing lists.
- Cost-per-wear and wardrobe statistics.

### Phase 4 — sharing and gifting

- Read-only wishlist links or files that open without an account.
- Gift reservation so people don't buy the same gift twice.
- Per-collection privacy.

### Phase 5 — backup and sync

- Encrypted backup and restore files.
- Optional sync across devices, using a self-hosted or end-to-end encrypted service chosen by the owner.

### Phase 6 — optional visual search and enrichment

- Similar items from a photo.
- Attribute tagging for links with sparse data.
- Uses the "Optional AI models" rules below: evidence stays separate from suggestions, and every tag can be corrected.

Sources: [BEUC complaint about Shein](https://www.storyboard18.com/amp/brand-marketing/shein-hit-with-eu-complaint-over-dark-patterns-in-app-website-68964.htm), [Dark patterns at scale, 11K shopping sites](https://arxiv.org/pdf/2107.07893), [Forbes India on dark patterns](https://www.magzter.com/ja/stories/business/Forbes-India/CLICK-BUY-REGRET), [Universal wishlist apps compared](https://giftlist.com/blog/10-best-universal-wishlist-apps-in-2025-ranked-and-reviewed), [Good On You wardrobe app test](https://goodonyou.eco/wardrobe-organising-apps/), [Whering best wardrobe apps](https://whering.co.uk/best-wardrobe-apps-2025), [MediaPost on fit and returns](https://www.mediapost.com/publications/article/317614/retail-search-fit-recommendations-fail-to-curtai.html), [Baymard product page research](https://www.baymard.com/research/product-page), [Clutch on AI shopping features](https://clutch.co/resources/ai-shopping-features).

## Implemented foundation

Discovery UI, searchable imported catalog, eligible-merchant link extraction, ProductGroup handling, source evidence, owner-scoped persistence, named collections, product comparisons, curated sourcing links, and responsive/accessibility behavior.

## Next: real multi-store search

1. Choose initial merchant feeds, affiliate APIs, marketplace APIs, or direct seller agreements. Record permitted fields, access terms, geographical coverage, refresh limits, and failure behavior per source.
2. Ingest sources with scheduled/background jobs, retries, per-source budgets, and operational visibility. Replace the current synchronous bounded import with a job when workloads justify it.
3. Separate canonical product/variant identity from seller offers in indexed storage. Match exact products using GTIN/MPN/brand/variant evidence; present uncertain or visually similar matches separately.
4. Add query interpretation, catalog indexes, pagination, and relevance measurements using real queries.
5. Keep currencies original. Add destination, shipping, and duties only when evidence supports a delivered-price estimate. Separate quote-required wholesale prices from retail prices.

Acceptance: one query retrieves current offers from multiple connected sources, explains coverage and freshness, and groups exact variants without mixing similar items.

## Next: deeper seller discovery

Add permitted supplier-directory integrations, seller submissions, public business contact extraction, provenance, contact verification status, minimum orders, tiered prices, sample availability, lead times, and shipping regions. Distinguish a marketplace from the individual sellers on it. Private sellers share contact details voluntarily. Define moderation and seller verification before accepting public submissions.

Acceptance: sourcing filters return specific sellers with traceable, appropriately shared contact information and wholesale terms where provided.

## Next: catalog refinement and freshness

Add editable product annotations, refresh-from-source actions, saved collection reassignment, price history, stale-offer warnings, deletion/export controls, and update jobs. Preserve imported evidence separately from user annotations. On the hosted web app, expand the merchant allowlist after fixture and live validation; do not replace the server's SSRF boundary with unchecked arbitrary fetches. Native clients fetch from the user's own device, so they accept any public host (no address literals or local names).

Acceptance: users can correct their catalog, refresh a listing without losing notes, and distinguish current facts from stale or user-entered information.

## Optional AI models

Choose the first provider and budget with the owner before enabling paid inference. Useful initial tasks are category/attribute enrichment, multilingual query interpretation, and visual similarity. AI should fill a demonstrated gap after structured data and source APIs.

Implement the chosen provider server-side, with credentials configured through runtime secrets. Configure a model identifier, explicit per-task inputs, structured output validation, timeouts, and usage limits. Add a second provider adapter when it is actually needed. Never send account identity or unrelated private catalog data by default.

Model-generated suggestions must remain separate from extracted evidence. Models must not invent seller contacts, prices, stock, ingredients, or quality claims. Do not auto-fetch model-proposed URLs without applying the import policy. Evaluate against a representative labeled fixture set before showing AI enrichment as a default.

Acceptance: an authorized model can be enabled or disabled, improves a measured task, and fails back to deterministic behavior without leaking secrets or exceeding its budget.

## Before opening hosted access to more users

Private preview is the first deployment. Before changing the audience, verify gateway behavior for that audience, abuse/rate controls, concurrent import quotas, source agreements, user data isolation, account deletion/export, error monitoring, and provider spending limits. Keep source and hosting visibility separate.
