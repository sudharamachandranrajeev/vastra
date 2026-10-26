import retailerData from "../native/assets/data/retailers.json";

export const supportedRetailers = retailerData;

export class ImportError extends Error {
  constructor(message: string, public status = 422) { super(message); }
}

export function validateProductUrl(input: unknown): URL {
  if (typeof input !== "string" || input.length > 2048) throw new ImportError("Enter a product link, up to 2,048 characters.", 400);
  let url: URL;
  try { url = new URL(input.trim()); } catch { throw new ImportError("Enter a complete HTTPS product link.", 400); }
  if (url.protocol !== "https:" || url.username || url.password || url.port) throw new ImportError("Use an HTTPS store link without credentials or a custom port.", 400);
  const hostname = url.hostname.replace(/^www\./, "");
  if (!(supportedRetailers as readonly string[]).includes(hostname)) throw new ImportError("This store is not supported yet. See the supported stores below; more sources are planned.", 422);
  url.hash = "";
  for (const key of [...url.searchParams.keys()]) if (/^(utm_|fbclid$|gclid$)/i.test(key)) url.searchParams.delete(key);
  return url;
}

export function safeImageUrl(input: unknown, base?: string): string | null {
  if (typeof input !== "string" || input.length > 4096) return null;
  try {
    const url = new URL(input, base);
    if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
    if (!/^(?:[a-z0-9-]+\.)+[a-z]{2,}$/i.test(url.hostname) || /(?:^|\.)(localhost|local|internal|test|invalid)$/i.test(url.hostname)) return null;
    return url.href;
  } catch { return null; }
}
