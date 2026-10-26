import { and, eq } from "drizzle-orm";
import { getDb } from "@/db";
import { products, saved } from "@/db/schema";
import { sampleProducts } from "@/lib/catalog";
import { requireUser, apiError, readJson } from "@/lib/api";
import { ImportError } from "@/lib/import-policy";

export async function POST(request: Request) {
  try {
    const user = await requireUser(request);
    const { productId, collection = "My edit", remove = false } = await readJson(request);
    if (typeof productId !== "string" || productId.length > 100 || typeof collection !== "string" || !collection.trim() || collection.length > 60 || typeof remove !== "boolean") throw new ImportError("Invalid collection details.", 400);
    const db = getDb();
    if (!sampleProducts.some(p => p.id === productId)) {
      const [owned] = await db.select({ id: products.id }).from(products).where(and(eq(products.id, productId), eq(products.ownerId, user.userId))).limit(1);
      if (!owned) throw new ImportError("Product not found in your catalog.", 404);
    }
    if (remove) await db.delete(saved).where(and(eq(saved.ownerId, user.userId), eq(saved.productId, productId)));
    else await db.insert(saved).values({ ownerId: user.userId, productId, collection: collection.trim(), createdAt: Date.now() }).onConflictDoUpdate({ target: [saved.ownerId, saved.productId], set: { collection: collection.trim() } });
    return Response.json({ ok: true });
  } catch (error) { return apiError(error); }
}
