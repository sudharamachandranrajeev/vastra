import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { build } from "esbuild";
import { Miniflare } from "miniflare";

// Return raw responses: Undici's fetchMock bridge follows redirects itself,
// which would hide the Worker's redirect validation from this test.
const responses = new Map<string, () => Response>();
const requests: string[] = [];
let mf: Miniflare;
before(async () => {
  const bundle = await build({ entryPoints: ["tests/import.worker.ts"], bundle: true, write: false, format: "esm", platform: "browser", target: "es2022" });
  mf = new Miniflare({ modules: true, script: bundle.outputFiles[0].text, compatibilityDate: "2026-05-15", cf: false,
    outboundService(request) {
      requests.push(request.url);
      return responses.get(request.url)?.() ?? new Response("Unexpected outbound request", { status: 599 });
    },
  });
  await mf.ready;
});
after(async () => { await mf?.dispose(); });
const call = (url: string) => mf.dispatchFetch("http://localhost/", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ url }) });

test("real Worker HTMLRewriter extracts JSON-LD and persists source fidelity", async () => {
  responses.set("https://www.everlane.com/products/test", () => new Response(`<!doctype html><html><head><title>Shirt</title><script type="application/ld+json">${JSON.stringify({ "@type": "Product", name: "Real parser shirt", offers: { "@type": "Offer", price: "45", priceCurrency: "GBP" } })}</script></head></html>`, { headers: { "Content-Type": "text/html" } }));
  const response = await call("https://www.everlane.com/products/test");
  assert.equal(response.status, 200);
  const p = await response.json() as { name: string; offers: { price: number; currency: string }[] };
  assert.equal(p.name, "Real parser shirt"); assert.equal(p.offers[0].currency, "GBP"); assert.equal(p.offers[0].price, 45);
});

test("redirects to an internal address are rejected before fetching it", async () => {
  responses.set("https://www.nike.com/redirect", () => new Response("", { status: 302, headers: { Location: "http://169.254.169.254/latest/meta-data" } }));
  assert.equal((await call("https://www.nike.com/redirect")).status, 400);
  assert.equal(requests.some(url => url.includes("169.254.169.254")), false);
});

test("retailer anti-bot responses surface a useful import error", async () => {
  responses.set("https://www.nike.com/blocked", () => new Response("No", { status: 403, headers: { "Content-Type": "text/html" } }));
  const response = await call("https://www.nike.com/blocked");
  assert.equal(response.status, 422); assert.match(await response.text(), /restrict automated access/);
});

test("non-HTML and oversized pages are rejected", async () => {
  responses.set("https://www.nike.com/image", () => new Response("image", { headers: { "Content-Type": "image/png" } }));
  assert.equal((await call("https://www.nike.com/image")).status, 422);
  responses.set("https://www.nike.com/large", () => new Response("x".repeat(2_000_001), { headers: { "Content-Type": "text/html" } }));
  assert.equal((await call("https://www.nike.com/large")).status, 422);
});

test("redirect loops terminate", async () => {
  responses.set("https://www.nike.com/loop", () => new Response("", { status: 302, headers: { Location: "/loop" } }));
  const response = await call("https://www.nike.com/loop");
  assert.equal(response.status, 422); assert.match(await response.text(), /too many/);
});
