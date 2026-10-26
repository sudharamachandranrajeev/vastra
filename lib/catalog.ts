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

export const sellers = [
  { name: "Nicobar", country: "India", kind: "Independent", categories: ["Clothing", "Accessories"], description: "Contemporary Indian design, natural fabrics, and thoughtfully made everyday pieces.", url: "https://www.nicobar.com", contact: "https://www.nicobar.com/pages/contact-us", initials: "Ni", color: "#e9e8dc" },
  { name: "Etsy", country: "Global", kind: "Marketplace", categories: ["Clothing", "Accessories", "Footwear"], description: "Discover individual vintage sellers, independent makers, and handmade accessories.", url: "https://www.etsy.com", contact: "https://www.etsy.com", initials: "Et", color: "#f4e3d4" },
  { name: "Faire", country: "Global", kind: "Wholesale", categories: ["Clothing", "Accessories", "Beauty", "Body care"], description: "Independent brands for retail buyers. Minimum orders and territories vary by brand.", url: "https://www.faire.com", contact: "https://www.faire.com", initials: "Fa", color: "#e4e8e3" },
  { name: "Good On You", country: "Global", kind: "Directory", categories: ["Clothing", "Footwear", "Accessories"], description: "Explore fashion brands and read the directory’s published sustainability assessments.", url: "https://directory.goodonyou.eco", contact: "https://goodonyou.eco/contact/", initials: "Go", color: "#e5e7d9" },
  { name: "Sephora", country: "Global", kind: "Retail", categories: ["Beauty", "Fragrance", "Body care"], description: "Beauty, fragrance, and personal care. Select your region to check local availability.", url: "https://www.sephora.com", contact: "https://www.sephora.com/beauty/customer-service", initials: "Se", color: "#e9e1e5" },
  { name: "IndiaMART", country: "India", kind: "Wholesale", categories: ["Clothing", "Footwear", "Accessories", "Beauty", "Body care"], description: "A supplier marketplace for sourcing and wholesale inquiries. Verify sellers before ordering.", url: "https://www.indiamart.com", contact: "https://www.indiamart.com", initials: "IM", color: "#e1e7ed" },
];

const photo = (id: string) => `https://images.unsplash.com/${id}?auto=format&fit=crop&w=900&q=85`;
const examples: [string, Category, string, string, number, string, string, string][] = [
  ["The tailored cotton shirt", "Clothing", "A little polish for the everyday", "photo-1598033129183-c4f50c736f10", 49, "Cotton", "White", "USD"],
  ["The everyday city backpack", "Accessories", "Room for the little things", "photo-1553062407-98eeb64c6a62", 89, "Woven textile", "Navy", "EUR"],
  ["The everyday court sneaker", "Footwear", "Made for taking the long way", "photo-1549298916-b41d501d3772", 75, "Leather", "Terracotta", "GBP"],
  ["A moment of rose", "Fragrance", "Floral, soft, quietly memorable", "photo-1541643600914-78b084683601", 4200, "Eau de parfum", "50 ml", "INR"],
  ["The statement drop earrings", "Accessories", "A little everyday statement", "photo-1535632066927-ab7c9ab60908", 35, "See seller details", "Silver and blue", "USD"],
  ["The essential cotton tee", "Clothing", "Your wardrobe, simplified", "photo-1521572163474-6864f9cf17ab", 29, "Cotton", "Off-white", "EUR"],
  ["Daily hydration serum", "Beauty", "A considered skincare ritual", "photo-1608571423902-eed4a5ad8108", 28, "See seller ingredients", "30 ml", "GBP"],
  ["The quilted crossbody", "Accessories", "Small bag, big possibilities", "photo-1548036328-c9fa89d128fa", 79, "Leather", "Black", "USD"],
  ["The weekend graphic tee", "Clothing", "A little personality for the weekend", "photo-1576566588028-4147f3842f27", 69, "Cotton", "Cream", "EUR"],
  ["Restorative hair mask", "Body care", "A little care for wash day", "photo-1608248543803-ba4f8c70ae0b", 1490, "See seller ingredients", "200 ml", "INR"],
  ["The weekend runner", "Footwear", "Comfort in every direction", "photo-1542291026-7eec264c27ff", 99, "Textile", "Red", "USD"],
  ["Soft light sunglasses", "Accessories", "A fresh point of view", "photo-1511499767150-a48a237f0083", 39, "Metal frame", "Gold and green", "GBP"],
];

export const sampleProducts: Product[] = examples.map(([name, category, description, image, price, material, color, currency], i) => ({
  id: `sample-${i + 1}`,
  name, category, description, images: [photo(image)], brand: "THE VASTRA EDIT", material, color,
  sizes: category === "Clothing" ? ["XS", "S", "M", "L", "XL"] : [],
  offers: [{ seller: "Illustrative offer", price, currency, availability: "Sample — not live stock", url: "" }],
  sourceUrl: "", checkedAt: "", sample: true, extraction: "sample",
}));

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
