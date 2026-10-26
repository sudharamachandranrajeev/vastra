import type { Product, Category, Offer } from "./catalog";
import { ImportError, safeImageUrl } from "./import-policy";

type Obj = Record<string, unknown>;
const object = (v: unknown): Obj => v && typeof v === "object" && !Array.isArray(v) ? v as Obj : {};
const list = (v: unknown): unknown[] => v == null ? [] : Array.isArray(v) ? v : [v];
const string = (v: unknown, limit = 2000): string => typeof v === "string" ? v.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, limit) : "";

export type PageData = { jsonLd: unknown[]; meta: Record<string, string>; title: string };

export function categoryFor(text: string): Category {
  if (/\bbody\b|lotion|shower|deodorant|soap/i.test(text)) return "Body care";
  if (/perfume|parfum|fragrance|cologne/i.test(text)) return "Fragrance";
  if (/serum|cosmetic|makeup|lipstick|skincare|cleanser|moisturi[sz]er/i.test(text)) return "Beauty";
  if (/shoe|sneaker|boot|sandal|loafer|trainer|runner/i.test(text)) return "Footwear";
  if (/bag|jewel|necklace|earring|\bring\b|watch|sunglass|belt|scarf|crossbody/i.test(text)) return "Accessories";
  return "Clothing";
}

function productNodes(value: unknown, depth = 0): Obj[] {
  if (depth > 12) return [];
  if (Array.isArray(value)) return value.flatMap(v => productNodes(v, depth + 1));
  const node = object(value);
  if (list(node["@type"]).some(t => t === "Product" || t === "ProductGroup" || t === "https://schema.org/Product" || t === "https://schema.org/ProductGroup")) return [node];
  return Object.values(node).flatMap(v => typeof v === "object" && v !== null ? productNodes(v, depth + 1) : []);
}

function amount(value: unknown): number | null {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (typeof value === "string" && !/^\d+(\.\d+)?$/.test(value.trim())) return null;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

export function extractProduct(data: PageData, sourceUrl: string): Product {
  const nodes = data.jsonLd.flatMap(v => productNodes(v));
  const distinct = new Map(nodes.map(n => [string(n.sku) || string(n["@id"]) || string(n.name), n]));
  const matchesSource = (value: unknown) => {
    if (typeof value !== "string" || !value) return false;
    try { const candidate = new URL(value, sourceUrl); candidate.hash = ""; return candidate.href === sourceUrl; } catch { return false; }
  };
  const isPrimary = (n: Obj) => [n.url, n["@id"], ...list(n.offers).map(o => object(o).url)].some(matchesSource);
  const primary = [...distinct.values()].filter(isPrimary);
  // A ProductGroup owns its size/color variants. Only select a specific variant
  // when its source URL matches; a group's default price is not every size's price.
  const variantMatches = nodes.flatMap(group => list(group.hasVariant).map(object).filter(isPrimary).map(variant => ({ ...group, ...variant })));
  if (variantMatches.length > 1 || (!variantMatches.length && primary.length !== 1 && distinct.size > 1)) throw new ImportError("This page contains multiple products. Please paste a link to one specific product or variant.");
  const node = variantMatches[0] ?? primary[0] ?? nodes[0] ?? {};
  const meta = data.meta;
  const hasProductMetadata = /product/i.test(meta["og:type"] ?? "") || Boolean(meta["product:price:amount"]);
  if (!nodes.length && !hasProductMetadata) throw new ImportError("No product data was found. The store may block imports or this may not be a product page. Try another product link.");
  const name = string(node.name, 250) || string(meta["og:title"], 250) || string(data.title, 250);
  if (!name) throw new ImportError("This page did not provide a product name. Try a different product link.");
  const host = new URL(sourceUrl).hostname.replace(/^www\./, "");
  const brand = string(object(node.brand).name, 120) || string(node.brand, 120) || host;
  const description = string(node.description) || string(meta["og:description"]) || string(meta.description);
  const images = [...new Set([...list(node.image).map(i => typeof i === "string" ? i : object(i).url), meta["og:image"]].map(i => safeImageUrl(i, sourceUrl)).filter((i): i is string => Boolean(i)))].slice(0, 8);
  const offerNodes = list(node.offers).flatMap(o => {
    const value = object(o);
    if (value["@type"] === "AggregateOffer") return list(value.offers);
    return [value];
  });
  const offers: Offer[] = offerNodes.slice(0, 30).map(value => {
    const o = object(value);
    const currency = string(o.priceCurrency, 20).toUpperCase();
    return {
      seller: string(object(o.seller).name, 120) || host,
      url: sourceUrl,
      price: amount(o.price),
      currency: /^[A-Z]{3}$/.test(currency) ? currency : null,
      availability: string(o.availability, 100).replace(/^https?:\/\/schema.org\//, "") || "Unknown",
    };
  });
  if (!offers.length) {
    const currency = string(meta["product:price:currency"], 20).toUpperCase();
    offers.push({ seller: host, url: sourceUrl, price: amount(meta["product:price:amount"]), currency: /^[A-Z]{3}$/.test(currency) ? currency : null, availability: "Unknown" });
  }
  return {
    id: crypto.randomUUID(), name, brand, description, images, offers, sourceUrl,
    category: categoryFor(`${string(node.category)} ${name}`),
    color: string(node.color, 120) || null, material: string(node.material, 200) || null,
    sizes: [...new Set([...list(node.size), ...list(node.hasVariant).map(v => object(v).size)].map(v => typeof v === "number" ? String(v) : string(v, 50)).filter(Boolean))].slice(0, 30),
    checkedAt: new Date().toISOString(), sample: false,
    extraction: nodes.length ? "structured" : "metadata",
  };
}
