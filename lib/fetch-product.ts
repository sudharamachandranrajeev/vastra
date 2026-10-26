import { ImportError, validateProductUrl } from "./import-policy";
import { extractProduct, type PageData } from "./extract-product";

export async function importProduct(input: unknown) {
  let url = validateProductUrl(input);
  const signal = AbortSignal.timeout(15_000);
  for (let redirects = 0; redirects <= 4; redirects++) {
    const response = await fetch(url.href, {
      redirect: "manual", signal,
      headers: { "User-Agent": "Vastra/0.1 (+product-catalog-import)", Accept: "text/html,application/xhtml+xml" },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      await response.body?.cancel();
      if (!location) throw new ImportError("The store returned an incomplete redirect.");
      url = validateProductUrl(new URL(location, url).href);
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new ImportError(`The store could not share this page (HTTP ${response.status}). Try another link; some stores restrict automated access.`);
    }
    if (!/text\/html|application\/xhtml\+xml/i.test(response.headers.get("content-type") ?? "")) {
      await response.body?.cancel();
      throw new ImportError("This link does not return a product web page.");
    }
    if (Number(response.headers.get("content-length")) > 2_000_000) {
      await response.body?.cancel();
      throw new ImportError("This page is too large to import. Try another product link.");
    }
    const reader = response.body?.getReader();
    if (!reader) throw new ImportError("The store returned an empty page.");
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > 2_000_000) { await reader.cancel(); throw new ImportError("This page is too large to import."); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const html = new TextDecoder().decode(bytes);
    const data: PageData = { jsonLd: [], meta: {}, title: "" };
    let scriptText = "";
    const rewriter = new HTMLRewriter()
      .on('script[type="application/ld+json"]', {
        element() { scriptText = ""; },
        text(chunk) {
          scriptText += chunk.text;
          if (chunk.lastInTextNode) { try { data.jsonLd.push(JSON.parse(scriptText)); } catch { /* fall back to product metadata */ } }
        },
      })
      .on("meta", { element(element) {
        const name = element.getAttribute("property") ?? element.getAttribute("name");
        const content = element.getAttribute("content");
        if (name && content) data.meta[name.toLowerCase()] = content;
      } })
      .on("title", { text(chunk) { data.title += chunk.text; } });
    await rewriter.transform(new Response(html)).text();
    return extractProduct(data, url.href);
  }
  throw new ImportError("This link redirected too many times. Paste the final product page URL.");
}
