import { and, eq, desc, count } from "drizzle-orm";
import { getDb } from "@/db";
import { products, saved } from "@/db/schema";
import { requireUser, apiError, readJson } from "@/lib/api";
import { importProduct } from "@/lib/fetch-product";
import { ImportError, validateProductUrl } from "@/lib/import-policy";

export async function GET() {
  try {
    const user = await requireUser();
    const db = getDb();
    const [entries, saves] = await Promise.all([
      db.select().from(products).where(eq(products.ownerId, user.userId)).orderBy(desc(products.createdAt)).limit(200),
      db.select().from(saved).where(eq(saved.ownerId, user.userId)),
    ]);
    return Response.json({ products: entries.map(e => JSON.parse(e.document)), saved: saves }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return apiError(error); }
}

export async function POST(request: Request) {
  try {
    const user = await requireUser(request);
    const { url } = await readJson(request);
    const sourceUrl = validateProductUrl(url).href;
    const db = getDb();
    const existing = await db.select().from(products).where(and(eq(products.ownerId, user.userId), eq(products.sourceUrl, sourceUrl))).limit(1);
    if (existing.length) return Response.json({ product: JSON.parse(existing[0].document), existing: true });
    const [limit] = await db.select({ value: count() }).from(products).where(eq(products.ownerId, user.userId));
    if (limit.value >= 200) throw new ImportError("Your catalog has reached the initial limit of 200 imports.", 429);
    const product = await importProduct(sourceUrl);
    await db.insert(products).values({ id: product.id, ownerId: user.userId, sourceUrl: product.sourceUrl, document: JSON.stringify(product), createdAt: Date.now() }).onConflictDoNothing();
    const [entry] = await db.select().from(products).where(and(eq(products.ownerId, user.userId), eq(products.sourceUrl, product.sourceUrl))).limit(1);
    return Response.json({ product: JSON.parse(entry.document) }, { status: 201 });
  } catch (error) { return apiError(error); }
}

export async function DELETE(request: Request) {
  try {
    const user = await requireUser(request);
    const { id } = await readJson(request);
    if (typeof id !== "string" || id.length > 100) throw new ImportError("Invalid product.", 400);
    const db = getDb();
    const [owned] = await db.select({ id: products.id }).from(products).where(and(eq(products.id, id), eq(products.ownerId, user.userId))).limit(1);
    if (!owned) throw new ImportError("Product not found.", 404);
    await db.batch([
      db.delete(saved).where(and(eq(saved.ownerId, user.userId), eq(saved.productId, id))),
      db.delete(products).where(and(eq(products.ownerId, user.userId), eq(products.id, id))),
    ]);
    return Response.json({ ok: true });
  } catch (error) { return apiError(error); }
}
