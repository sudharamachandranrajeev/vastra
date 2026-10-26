# Vastra implementation roadmap

Launch preference: **global coverage, preserving original store currencies**.

## Native platforms

Standalone Flutter clients for Android, Windows and Linux now use local SQLite catalogs, direct eligible-store imports, named collections, refreshes and comparisons. Their data is separate from the authenticated hosted web catalog. Brahma integration is intentionally excluded by the owner’s preference. Native distribution includes Android signing, Windows installer/portable packages, Linux user installation and Arch packaging.

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

Add editable product annotations, refresh-from-source actions, saved collection reassignment, price history, stale-offer warnings, deletion/export controls, and update jobs. Preserve imported evidence separately from user annotations. Expand the merchant allowlist after fixture and live validation; do not replace the SSRF boundary with unchecked arbitrary fetches.

Acceptance: users can correct their catalog, refresh a listing without losing notes, and distinguish current facts from stale or user-entered information.

## Optional AI models

Choose the first provider and budget with the owner before enabling paid inference. Useful initial tasks are category/attribute enrichment, multilingual query interpretation, and visual similarity. AI should fill a demonstrated gap after structured data and source APIs.

Implement the chosen provider server-side, with credentials configured through runtime secrets. Configure a model identifier, explicit per-task inputs, structured output validation, timeouts, and usage limits. Add a second provider adapter when it is actually needed. Never send account identity or unrelated private catalog data by default.

Model-generated suggestions must remain separate from extracted evidence. Models must not invent seller contacts, prices, stock, ingredients, or quality claims. Do not auto-fetch model-proposed URLs without applying the import policy. Evaluate against a representative labeled fixture set before showing AI enrichment as a default.

Acceptance: an authorized model can be enabled or disabled, improves a measured task, and fails back to deterministic behavior without leaking secrets or exceeding its budget.

## Before opening hosted access to more users

Private preview is the first deployment. Before changing the audience, verify gateway behavior for that audience, abuse/rate controls, concurrent import quotas, source agreements, user data isolation, account deletion/export, error monitoring, and provider spending limits. Keep source and hosting visibility separate.
