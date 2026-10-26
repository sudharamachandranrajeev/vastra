import { test } from "node:test";
import assert from "node:assert/strict";
import { extractProduct, categoryFor, type PageData } from "../lib/extract-product";
import { validateProductUrl, safeImageUrl } from "../lib/import-policy";
import { filterProducts, lowestOffer, priceLabel, sampleProducts } from "../lib/catalog";

const url = "https://www.everlane.com/products/linen-shirt";
const page = (node: unknown): PageData => ({ jsonLd: [node], meta: {}, title: "" });
const product = { "@type": "Product", name: "Linen shirt", brand: { name: "Example" }, image: "/images/shirt.jpg", material: "Linen", color: "Sand", size: ["S", "M"], offers: { "@type": "Offer", price: "49.95", priceCurrency: "USD", availability: "https://schema.org/InStock" } };

test("imports nested graph product data and keeps original currency and source", () => {
  const p = extractProduct(page({ "@graph": [{ "@type": "Organization" }, product] }), url);
  assert.equal(p.name, "Linen shirt"); assert.equal(p.brand, "Example"); assert.equal(p.offers[0].price, 49.95); assert.equal(p.offers[0].currency, "USD");
  assert.equal(p.offers[0].availability, "InStock"); assert.equal(p.sourceUrl, url); assert.equal(p.sample, false); assert.equal(p.extraction, "structured");
  assert.equal(p.images[0], "https://www.everlane.com/images/shirt.jpg"); assert.deepEqual(p.sizes, ["S", "M"]);
});

test("missing price, materials and currency remain unknown", () => {
  const p = extractProduct(page({ "@type": "Product", name: "A shirt" }), url);
  assert.equal(p.material, null); assert.equal(p.offers[0].price, null); assert.equal(p.offers[0].currency, null); assert.equal(priceLabel(p.offers[0]), "Price unavailable");
});

test("product metadata is a fallback, unrelated web pages are rejected", () => {
  const p = extractProduct({ jsonLd: [], title: "Fallback", meta: { "og:type": "product", "og:title": "Face serum", "product:price:amount": "12", "product:price:currency": "EUR" } }, url);
  assert.equal(p.extraction, "metadata"); assert.equal(p.category, "Beauty"); assert.equal(p.offers[0].currency, "EUR");
  assert.throws(() => extractProduct({ jsonLd: [], meta: { "og:title": "Home" }, title: "Home" }, url), /No product data/);
});

test("does not mistake aggregate lowPrice for a buyable variant", () => {
  const p = extractProduct(page({ ...product, offers: { "@type": "AggregateOffer", lowPrice: "1", highPrice: "50", priceCurrency: "USD" } }), url);
  assert.equal(p.offers[0].price, null);
});

test("does not mix recommendations into one imported product", () => {
  assert.throws(() => extractProduct(page([product, { ...product, name: "Another shirt" }]), url), /multiple products/);
});

test("ProductGroup owns its size variants instead of treating them as recommendations", () => {
  const group = { ...product, "@type": "ProductGroup", "@id": "#shirt", hasVariant: [{ ...product, sku: "S", size: "S", offers: { ...product.offers, url: `${url}?size=S`, price: "39" } }, { ...product, sku: "M", size: "M" }] };
  const p = extractProduct(page([group, { "@type": "Product", name: "Related scarf" }]), url);
  assert.equal(p.name, "Linen shirt"); assert.deepEqual(p.sizes, ["S", "M"]); assert.equal(p.offers[0].price, 49.95);
  const variant = extractProduct(page(group), `${url}?size=S`);
  assert.equal(variant.offers[0].price, 39);
});

test("an exact source URL selects the primary product among recommendations", () => {
  const p = extractProduct(page([{ ...product, url }, { ...product, name: "Recommended sneaker", url: "https://www.everlane.com/other" }]), url);
  assert.equal(p.name, "Linen shirt");
});

test("invalid prices do not become zero or partial numbers", () => {
  for (const price of ["", "€19", "12abc", "1,000", -1, Infinity, null]) {
    const p = extractProduct(page({ ...product, offers: { price, priceCurrency: "EUR" } }), url);
    assert.equal(p.offers[0].price, null);
  }
  assert.equal(extractProduct(page({ ...product, offers: { price: 0, priceCurrency: "USD" } }), url).offers[0].price, 0);
});

test("untrusted structured-data links cannot replace the source", () => {
  const p = extractProduct(page({ ...product, image: "javascript:alert(1)", offers: { ...product.offers, url: "https://evil.example/buy" } }), url);
  assert.deepEqual(p.images, []); assert.equal(p.offers[0].url, url);
});

test("safe merchant URL canonicalization removes trackers but preserves variant selection", () => {
  assert.equal(validateProductUrl(`${url}?variant=123&utm_source=test&gclid=test#top`).href, `${url}?variant=123`);
});

test("URL policy rejects internal hosts, credentials, custom ports, deceptive hosts and schemes", () => {
  for (const value of ["http://www.nike.com/item", "https://localhost/a", "https://127.0.0.1", "https://[::1]", "https://169.254.169.254/latest", "https://nike.com.evil.example", "https://evil.nike.com", "https://nike.com@evil.example", "https://u:p@nike.com/item", "https://nike.com:8443/item", "file:///etc/passwd", "javascript:alert(1)", null]) assert.throws(() => validateProductUrl(value));
});

test("image URLs reject scripts, credentials and local destinations", () => {
  for (const value of ["javascript:alert(1)", "http://example.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://internal.local/a", "https://user:pass@example.com/a"]) assert.equal(safeImageUrl(value), null);
});

test("catalog search combines material, category, color and query words", () => {
  assert.equal(filterProducts(sampleProducts, "tailored cotton white", "Clothing").length, 1);
  assert.equal(filterProducts(sampleProducts, "cotton", "Footwear").length, 0);
  assert.equal(filterProducts(sampleProducts, "  TAILORED  ", "All discoveries")[0].id, "sample-1");
});

test("category classification covers fashion and personal care", () => {
  assert.equal(categoryFor("body lotion"), "Body care"); assert.equal(categoryFor("eau de parfum"), "Fragrance"); assert.equal(categoryFor("running sneaker"), "Footwear"); assert.equal(categoryFor("gold earrings"), "Accessories");
});

test("offer selection compares one currency and does not rank across currencies", () => {
  const base = sampleProducts[0];
  const usd = { seller: "A", price: 90, currency: "USD", url, availability: "Unknown" };
  const other = { ...usd, seller: "B", price: 70 };
  assert.equal(lowestOffer({ ...base, offers: [usd, other] })?.seller, "B");
  assert.equal(lowestOffer({ ...base, offers: [usd, { ...other, currency: "GBP" }] })?.seller, "A");
});
