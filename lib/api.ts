import { getChatGPTUser } from "@/app/chatgpt-auth";
import { ImportError } from "./import-policy";

export async function requireUser(request?: Request) {
  if (request && request.method !== "GET") {
    const origin = request.headers.get("origin");
    if (!origin || origin !== new URL(request.url).origin) throw new ImportError("Request must come from Vastra.", 403);
    if (!request.headers.get("content-type")?.includes("application/json")) throw new ImportError("Expected a JSON request.", 415);
    if (Number(request.headers.get("content-length")) > 16_384) throw new ImportError("Request too large.", 413);
  }
  const user = await getChatGPTUser();
  if (!user) throw new ImportError("Sign in to import products and save your collection.", 401);
  return user;
}

export function apiError(error: unknown) {
  if (error instanceof ImportError) return Response.json({ error: error.message }, { status: error.status });
  if (error instanceof SyntaxError) return Response.json({ error: "Invalid JSON request." }, { status: 400 });
  if (error instanceof Error && /abort|timeout/i.test(error.name)) return Response.json({ error: "The store took too long to respond. Please try again." }, { status: 504 });
  console.error("Vastra request failed", error instanceof Error ? error.name : "UnknownError");
  return Response.json({ error: "This request could not be completed. Please try again." }, { status: 500 });
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader();
  if (!reader) throw new ImportError("A JSON body is required.", 400);
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 16_384) { await reader.cancel(); throw new ImportError("Request too large.", 413); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const data: unknown = JSON.parse(new TextDecoder().decode(bytes));
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new ImportError("Expected a JSON object.", 400);
  return data as Record<string, unknown>;
}
