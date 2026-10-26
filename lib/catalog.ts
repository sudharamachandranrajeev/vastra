import productData from "../native/assets/data/products.json";
import sellerData from "../native/assets/data/sellers.json";

export const categories = ["All discoveries", "Clothing", "Footwear", "Accessories", "Beauty", "Fragrance", "Body care"] as const;
export type Category = typeof categories[number];
export type Offer = {
  seller: string;
  url: string;
  price: number | null;
  currency: string | null;
  availability: string;
};
export type Product = {
  id: string;
  name: string;
  brand: string;
  category: Category;
  description: string;
  images: string[];
  color: string | null;
  material: string | null;
  sizes: string[];
  offers: Offer[];
  sourceUrl: string;
  checkedAt: string;
  sample: boolean;
  extraction: "structured" | "metadata" | "sample";
};

export const sellers = sellerData;
export const sampleProducts = productData as Product[];

export function priceLabel(offer?: Offer) {
  if (!offer || offer.price === null || !offer.currency) return "Price unavailable";
  try { return new Intl.NumberFormat("en", { style: "currency", currency: offer.currency, maximumFractionDigits: 2 }).format(offer.price); }
  catch { return `${offer.currency} ${offer.price.toFixed(2)}`; }
}

export function filterProducts(products: Product[], query: string, category: string) {
  const tokens = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return products.filter(p => (category === "All discoveries" || p.category === category) && tokens.every(t => `${p.name} ${p.brand} ${p.category} ${p.description} ${p.material ?? ""} ${p.color ?? ""}`.toLowerCase().includes(t)));
}

export function lowestOffer(product: Product): Offer | undefined {
  const currencies = new Set(product.offers.filter(o => o.price !== null && o.currency).map(o => o.currency));
  if (currencies.size > 1) return product.offers[0];
  return [...product.offers].sort((a, b) => (a.price ?? Infinity) - (b.price ?? Infinity))[0];
}
