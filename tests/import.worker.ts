import { importProduct } from "../lib/fetch-product";
import { ImportError } from "../lib/import-policy";

// This Worker is bundled only by tests. It is never included in the app routes.
export default {
  async fetch(request: Request) {
    try { const { url } = await request.json() as { url: string }; return Response.json(await importProduct(url)); }
    catch (error) { return Response.json({ error: error instanceof Error ? error.message : "Error" }, { status: error instanceof ImportError ? error.status : 500 }); }
  },
};
