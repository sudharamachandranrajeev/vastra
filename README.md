# Vastra

A considered way to discover fashion, footwear, accessories, cosmetics, fragrance, and personal care. Vastra brings product links into a searchable personal catalog, with original-currency offers, saved collections, and a global sourcing directory.

![Vastra discovery interface](docs/preview-desktop.png)

## What works in this first release

- Responsive discovery UI with product search, category filters, and currency-scoped price sorting.
- Real server-side product-link imports using Schema.org Product / ProductGroup JSON-LD, with product metadata fallback.
- Product-group and source-URL selection that separates variants from recommendations.
- Product pages with imagery, brand, descriptions, materials, listed sizes, source offers, availability, and extraction timestamps. Missing fields remain unknown.
- ChatGPT sign-in and user-owned D1 persistence for imported products and named collections.
- Side-by-side comparison of up to four independently selected products.
- Curated independent, retail, wholesale, marketplace, and directory sources with public contact links.
- Original source links and deletion of owned imports, including their collection entries.
- Search handoffs to Google Shopping and Etsy.

**Coverage is intentionally explicit:** catalog search currently searches your imports and 12 clearly labeled inspiration samples. It does not yet query all retailers live. Seller-directory entries are curated sources, not automatically verified individual sellers. Sample prices, specifications, and photographs are illustrative, not offers for sale.

## Run locally

Requires Node.js 22.13+ and npm. The app uses Vinext (Next.js App Router on Vite), React, TypeScript, Cloudflare Workers, D1, and Drizzle.

```sh
npm ci
npm run build
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/0000_thick_carlie_cooper.sql
npm run dev -- --hostname 127.0.0.1 --port 5173
```

Apply that initial migration once to a new local database. Keep `.wrangler/state` between sessions. Later schema changes must append migrations; never replay or edit applied migrations. Local and hosted databases are separate.

Open http://127.0.0.1:5173. Use the account icon to sign in. The supplied Sites development integration simulates a loopback-only local account; production sign-in is handled by the Sites gateway. This local identity is for development only.

No AI key is required for product imports. No credentials belong in source control.

## Verification

```sh
npm run typecheck
npm test
npx playwright install chromium
npm run test:e2e
```

Browser tests require the local migration above. To use an existing system Chromium:

```sh
VASTRA_BROWSER_PATH=/usr/bin/chromium npm run test:e2e
```

Unit tests cover extraction, missing/invalid data, product-group selection, currencies, search, and URL policy. Worker integration tests run the actual HTML parser and bounded fetch pipeline in Miniflare with a controlled outbound transport. Browser tests exercise desktop/mobile navigation, search, currency sorting, comparisons, seller filtering, authenticated collection persistence, import errors, and write authorization. The test account's `Travel wardrobe` sample save is created and removed by the collection test; do not use that development collection for personal records.

A live Allbirds product import was also verified manually during development. Live retailer availability is not a deterministic test dependency.

## Import boundaries

`lib/import-policy.ts` owns the exact retailer host allowlist. Every fetch and redirect is validated against it. Only HTTPS, standard ports, and credential-free URLs are accepted. Arbitrary hosts, untrusted subdomains, private addresses, and internal services are never fetched. Imports have a 15-second deadline, a 2 MB response limit, and at most four followed redirects. URLs retain variant selectors while common tracking parameters are removed.

Eligible stores are listed inside the import dialog. A listed store can still block automated requests or omit usable product data. Vastra reports that instead of inventing details or circumventing access controls. For a known working starting example, try:

```text
https://www.allbirds.com/products/mens-wool-runners
```

Vastra retains source image URLs instead of copying merchant photographs. Sample photography uses Unsplash URLs. Availability and prices are snapshots, not checkout guarantees. Shipping, taxes, duties, returns, and final availability must be checked with the source. Prices are never ranked across different currencies. Comparisons are not assertions of exact product equivalence or independent quality certification.

## Ownership and deployment

- `app/`: page and API routes; `app/chatgpt-auth.ts` reads platform-authenticated identity.
- `components/vastra-app.tsx`: discovery, catalog, collections, sourcing, imports, and comparison UI.
- `lib/catalog.ts`: shared product/offer types, inspiration catalog, sourcing directory, and search helpers.
- `lib/import-policy.ts`, `lib/fetch-product.ts`, `lib/extract-product.ts`: fetch policy, bounded retrieval, and evidence-preserving extraction.
- `db/schema.ts`, `drizzle/`: user-owned catalog/collection schema and append-only migrations.
- `.openai/hosting.json`: Sites project identity and D1 binding; no secrets.
- `worker/` and `scripts/`: supplied Sites/Vinext runtime and portable tooling.

API writes require authenticated identity, same-origin JSON requests, and bounded bodies. Saved products, reads, and deletes are scoped to the authenticated user ID. Canonical source URLs are unique per owner. The initial catalog limit is 200 imported products per account; pagination and large-catalog search are future work.

**Deploy behind the Sites authentication gateway.** The app trusts dispatch-owned `oai-authenticated-user-*` headers. If self-hosting elsewhere, replace that boundary with verified authentication and strip untrusted identity headers at the proxy; never expose this Worker directly while trusting client-supplied identity headers. Production mock sign-in is disabled by the supplied Sites build integration.

Sites publication synchronizes the exact Git source commit, packages the build, applies schema migrations, and deploys a private authenticated preview. A public source repository does not make the hosted app public.

See [the implementation roadmap](docs/ROADMAP.md) for global search, seller discovery, price freshness, and optional AI.
