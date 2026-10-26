"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode, type FormEvent } from "react";
import { ArrowDownUp, ArrowRight, ArrowUpRight, Bookmark, Check, ChevronDown, Compass, ExternalLink, Globe2, Heart, Layers3, Leaf, Link2, Loader2, Plus, Search, SlidersHorizontal, Sparkles, Trash2, X } from "lucide-react";
import { categories, filterProducts, lowestOffer, priceLabel, sampleProducts, sellers, type Product, type Category } from "@/lib/catalog";
import { supportedRetailers } from "@/lib/import-policy";

type View = "Discover" | "My catalog" | "Sellers" | "Collections";
type Save = { productId: string; collection: string };
type Props = { user: { name: string } | null };

async function api<T>(path: string, body?: unknown, method = "POST"): Promise<T> {
  const response = await fetch(path, body === undefined ? { cache: "no-store" } : { method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const result = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(result.error ?? "Something went wrong. Please try again.");
  return result;
}

function Modal({ title, children, close, wide = false }: { title: string; children: ReactNode; close: () => void; wide?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    const trigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialog?.showModal();
    return () => {
      dialog?.close();
      // React removes the dialog before the native close algorithm can reliably
      // return focus. Keep keyboard users at the control that opened it.
      if (trigger?.isConnected) trigger.focus();
    };
  }, []);
  return <dialog ref={ref} className={`modal ${wide ? "modal-wide" : ""}`} aria-label={title} onCancel={close} onClick={e => { if (e.target === e.currentTarget) { const r = e.currentTarget.getBoundingClientRect(); if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) close(); } }}>
    <header className="modal-head"><span className="eyebrow">VASTRA / {title}</span><button className="icon-button" aria-label="Close dialog" onClick={close}><X size={20} /></button></header>
    {children}
  </dialog>;
}

function ProductImage({ product, className = "" }: { product: Product; className?: string }) {
  const [failed, setFailed] = useState(false);
  if (!product.images.length || failed) return <div className={`image-placeholder ${className}`}><Layers3 size={36} strokeWidth={1} /><span>Image unavailable</span></div>;
  return <img className={className} src={product.images[0]} alt={product.name} loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)} />;
}

export default function VastraApp({ user }: Props) {
  const [ready, setReady] = useState(false);
  const [view, setView] = useState<View>("Discover");
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<Category>("All discoveries");
  const [imported, setImported] = useState<Product[]>([]);
  const [saves, setSaves] = useState<Save[]>([]);
  const [loaded, setLoaded] = useState(!user);
  const [sort, setSort] = useState("Recommended");
  const [currency, setCurrency] = useState("All currencies");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [sampleVisible, setSampleVisible] = useState(true);
  const [selected, setSelected] = useState<Product | null>(null);
  const [showImport, setShowImport] = useState(false);
  const [importUrl, setImportUrl] = useState("");
  const [importError, setImportError] = useState("");
  const [importBusy, setImportBusy] = useState(false);
  const [comparison, setComparison] = useState<string[]>([]);
  const [showCompare, setShowCompare] = useState(false);
  const [notice, setNotice] = useState("");
  const [saveBusy, setSaveBusy] = useState(false);
  const [sellerKind, setSellerKind] = useState("All sellers");
  const [activeCollection, setActiveCollection] = useState("All collections");
  const [collectionName, setCollectionName] = useState("My edit");
  const [showAbout, setShowAbout] = useState(false);
  const [catalogError, setCatalogError] = useState("");
  const [reload, setReload] = useState(0);

  useEffect(() => { setReady(true); }, []);
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    api<{ products: Product[]; saved: Save[] }>("/api/catalog")
      .then(data => { if (!cancelled) { setImported(data.products); setSaves(data.saved); setCatalogError(""); } })
      .catch(error => { if (!cancelled) setCatalogError(error.message); })
      .finally(() => { if (!cancelled) setLoaded(true); });
    return () => { cancelled = true; };
  }, [user, reload]);
  useEffect(() => { if (!notice) return; const timer = setTimeout(() => setNotice(""), 5000); return () => clearTimeout(timer); }, [notice]);

  const allProducts = useMemo(() => [...imported, ...sampleProducts], [imported]);
  const savedIds = new Set(saves.map(s => s.productId));
  const collections = [...new Set(saves.map(s => s.collection))];
  const currencies = [...new Set(allProducts.flatMap(p => p.offers.map(o => o.currency).filter((v): v is string => Boolean(v))))].sort();
  const results = useMemo(() => {
    let products = allProducts;
    if (view === "My catalog") products = imported;
    if (view === "Collections") products = products.filter(p => saves.some(s => s.productId === p.id && (activeCollection === "All collections" || s.collection === activeCollection)));
    if (!sampleVisible) products = products.filter(p => !p.sample);
    products = filterProducts(products, query, category).filter(p => currency === "All currencies" || p.offers.some(o => o.currency === currency));
    if (sort === "Name A–Z") products.sort((a, b) => a.name.localeCompare(b.name));
    if (sort === "Price: low to high" && currency !== "All currencies") products.sort((a, b) => Math.min(...a.offers.filter(o => o.currency === currency).map(o => o.price ?? Infinity)) - Math.min(...b.offers.filter(o => o.currency === currency).map(o => o.price ?? Infinity)));
    return products;
  }, [allProducts, imported, saves, view, activeCollection, sampleVisible, query, category, currency, sort]);
  const visibleSellers = sellers.filter(s => (sellerKind === "All sellers" || s.kind === sellerKind) && (category === "All discoveries" || s.categories.includes(category)) && `${s.name} ${s.description} ${s.country}`.toLowerCase().includes(query.toLowerCase().trim()));
  const compared = allProducts.filter(p => comparison.includes(p.id));

  function navigate(next: View) { setView(next); setQuery(""); setCategory("All discoveries"); setActiveCollection("All collections"); }
  function openImport(value = "") { setImportError(""); setImportUrl(value); setShowImport(true); }
  function toggleCompare(id: string) { setComparison(current => current.includes(id) ? current.filter(i => i !== id) : current.length < 4 ? [...current, id] : current); if (!comparison.includes(id) && comparison.length === 4) setNotice("Compare up to four products at a time."); }

  async function toggleSave(product: Product, collection = "My edit") {
    if (!user) { setNotice("Sign in to save your personal edit."); return; }
    if (saveBusy) return;
    if (catalogError) { setNotice("Reload your catalog before changing saved products."); return; }
    setSaveBusy(true);
    const remove = savedIds.has(product.id);
    try {
      await api("/api/saved", { productId: product.id, collection, remove });
      setSaves(current => remove ? current.filter(s => s.productId !== product.id) : [...current, { productId: product.id, collection }]);
      setNotice(remove ? "Removed from your collection." : `Saved to ${collection}.`);
    } catch (error) { setNotice((error as Error).message); }
    finally { setSaveBusy(false); }
  }

  async function importLink(event: FormEvent) {
    event.preventDefault();
    if (!user) { setImportError("Sign in to import products into your catalog."); return; }
    setImportBusy(true); setImportError("");
    try {
      const { product, existing } = await api<{ product: Product; existing?: boolean }>("/api/catalog", { url: importUrl });
      setImported(current => [product, ...current.filter(p => p.id !== product.id)]);
      setShowImport(false); setSelected(product);
      setNotice(existing ? "This product is already in your catalog." : "Product imported into your catalog.");
    } catch (error) { setImportError((error as Error).message); }
    finally { setImportBusy(false); }
  }

  async function removeProduct(product: Product) {
    if (!window.confirm(`Remove “${product.name}” from your catalog and collections?`)) return;
    try {
      await api("/api/catalog", { id: product.id }, "DELETE");
      setImported(current => current.filter(p => p.id !== product.id));
      setSaves(current => current.filter(s => s.productId !== product.id));
      setComparison(current => current.filter(id => id !== product.id));
      setSelected(null); setNotice("Product removed.");
    } catch (error) { setNotice((error as Error).message); }
  }

  return <div className="app-shell" aria-busy={!ready} inert={!ready}>
    <a href="#main" className="skip-link">Skip to content</a>
    <header className="topbar">
      <a className="brand" href="/" aria-label="Vastra home">vastra<span className="brand-leaf"><Leaf size={15} /></span><span className="brand-dot">.</span></a>
      <nav className="main-nav" aria-label="Main navigation">{(["Discover", "My catalog", "Sellers", "Collections"] as View[]).map(item => <button key={item} className={view === item ? "active" : ""} disabled={!ready} onClick={() => navigate(item)}>{item}{item === "Collections" && saves.length > 0 && <span className="nav-count">{saves.length}</span>}</button>)}</nav>
      <div className="header-actions"><span className="global-label"><Globe2 size={15} /> Global discovery</span><button className="button button-dark small" disabled={!ready} onClick={() => openImport()}><Plus size={16} /> Add a link</button><a className="avatar" title={user ? user.name : "Sign in with ChatGPT"} aria-label={user ? "Sign out" : "Sign in"} href={user ? "/signout-with-chatgpt?return_to=/" : "/signin-with-chatgpt?return_to=/"} target="_top">{user ? user.name.slice(0, 1).toUpperCase() : <Bookmark size={17} />}</a></div>
    </header>

    <main id="main">
      {view === "Discover" ? <section className="hero">
        <div className="hero-copy"><div className="eyebrow hero-eyebrow"><span className="tiny-star" aria-hidden="true"><Sparkles size={16} /></span> GOOD FINDS. GREAT POSSIBILITIES.</div><h1>A world of good finds.<br /><em>An edit that’s you.</em></h1><p>Discover fashion, beauty, and the people behind them.<br className="desktop-break" /> Bring your favorites together, beautifully.</p><form className="search-box" onSubmit={event => { event.preventDefault(); if (/^https?:\/\//i.test(query)) openImport(query); else document.getElementById("catalog-section")?.scrollIntoView({ behavior: "smooth" }); }}><Search size={21} /><input aria-label="Search products or paste a product link" disabled={!ready} placeholder="Search for a little something you’ll love…" value={query} onChange={e => setQuery(e.target.value)} /><button type="submit" aria-label="Search"><ArrowRight size={20} /></button></form><div className="search-hint"><span>Try a find:</span>{["cotton", "sneaker", "fragrance"].map(term => <button key={term} onClick={() => { setQuery(term); setCategory("All discoveries"); }}>{term}<ArrowUpRight size={11} /></button>)}</div></div>
        <div className="hero-visual"><img src="https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=1200&q=85" alt="An afternoon of fashion discovery in the city" fetchPriority="high" /><div className="hero-image-shade" /><span className="hero-image-label">CURATED BY YOU. DISCOVERED WITH VASTRA.</span><div className="floating-note"><span className="note-icon"><Sparkles size={18} /></span><div><strong>A good find is a beginning.</strong><span>Make room for something you love.</span></div></div></div>
      </section> : <section className="page-intro"><div className="eyebrow">YOUR WORLD, WELL CONSIDERED</div><h1>{view === "My catalog" ? "Your finds, together." : view === "Sellers" ? "Meet your next good source." : "A little more you."}</h1><p>{view === "My catalog" ? "Every product you import, organized in one beautiful place." : view === "Sellers" ? "Independent makers, trusted retailers, and places to source something different." : "Save what speaks to you. Build an edit of your own."}</p><div className="intro-actions"><div className="compact-search"><Search size={18} /><input aria-label={`Search ${view.toLowerCase()}`} value={query} onChange={e => setQuery(e.target.value)} placeholder={view === "Sellers" ? "Search sellers, countries, or specialties" : "Search your finds"} />{query && <button className="icon-button" aria-label="Clear search" onClick={() => setQuery("")}><X size={15} /></button>}</div>{view === "My catalog" && <button className="button button-dark" onClick={() => openImport()}><Plus size={17} /> Import a product</button>}</div></section>}

      <div className="value-strip"><span><Globe2 size={17} /> A global point of view</span><i /><span><Layers3 size={17} /> All your finds, one place</span><i /><span><Link2 size={17} /> Just paste a product link</span><button onClick={() => setShowAbout(true)}>A little about Vastra <ArrowUpRight size={14} /></button></div>

      <section id="catalog-section" className="catalog-section">
        <div className="section-heading"><div><div className="eyebrow">{view === "Discover" ? "THE DISCOVERY EDIT" : view === "Sellers" ? "FIND YOUR PEOPLE" : view === "Collections" ? "YOUR PERSONAL EDIT" : "YOUR PRODUCT LIBRARY"}</div><h2>{view === "Discover" ? "Worth a closer look" : view === "Sellers" ? "Good things start with good sources" : view === "Collections" ? "Collected with intention" : "A catalog, made yours"}<span className="heading-dot">.</span></h2></div><span className="quiet-label">{view === "Sellers" ? `${visibleSellers.length} sources to explore` : `${results.length} ${results.length === 1 ? "find" : "finds"} to explore`}</span></div>
        <div className="catalog-toolbar"><div className="category-tabs" role="group" aria-label="Product categories">{categories.map(item => <button key={item} aria-pressed={category === item} className={category === item ? "selected" : ""} onClick={() => setCategory(item)}>{item}</button>)}</div>{view !== "Sellers" && <button className={`filter-button ${filtersOpen ? "selected" : ""}`} aria-expanded={filtersOpen} onClick={() => setFiltersOpen(!filtersOpen)}><SlidersHorizontal size={15} /> Filters</button>}</div>
        {filtersOpen && view !== "Sellers" && <div className="filter-panel"><label>Store currency<select value={currency} onChange={e => { setCurrency(e.target.value); if (e.target.value === "All currencies" && sort === "Price: low to high") setSort("Recommended"); }}><option>All currencies</option>{currencies.map(c => <option key={c}>{c}</option>)}</select></label><label className="checkbox-label"><input type="checkbox" checked={sampleVisible} onChange={e => setSampleVisible(e.target.checked)} /> Include illustrative sample products</label><p>Prices stay in their original currency. Select one currency to sort by price.</p></div>}
        {view === "Collections" && <div className="collection-tabs">{["All collections", ...collections].map(c => <button key={c} onClick={() => setActiveCollection(c)} className={activeCollection === c ? "selected" : ""}><Bookmark size={14} />{c}</button>)}</div>}
        {view === "Sellers" && <div className="collection-tabs">{["All sellers", "Independent", "Marketplace", "Wholesale", "Retail", "Directory"].map(kind => <button key={kind} onClick={() => setSellerKind(kind)} className={sellerKind === kind ? "selected" : ""}>{kind}</button>)}</div>}
        {catalogError && <div className="error-banner" role="alert">Your saved catalog could not load. {catalogError}<button onClick={() => { setLoaded(false); setReload(n => n + 1); }}>Retry</button></div>}
        {view !== "Sellers" && <div className="results-meta"><p>{query ? <>Results for <strong>“{query}”</strong> <button onClick={() => setQuery("")} className="text-link">Clear</button></> : view === "Discover" ? "A few things to get your inspiration going." : view === "My catalog" ? "Imported directly from the product links you share." : "All the pieces you keep coming back to."}</p><label className="sort-label"><ArrowDownUp size={13} /><span className="sr-only">Sort products</span><select value={sort} onChange={e => setSort(e.target.value)}><option>Recommended</option><option>Name A–Z</option><option disabled={currency === "All currencies"}>Price: low to high</option></select><ChevronDown size={12} /></label></div>}

        {!loaded && view !== "Sellers" ? <div className="empty-state"><Loader2 className="spin" /><h3>Gathering your finds…</h3></div> : view === "Sellers" ? <><p className="source-note">A curated starting directory. Contacts open the source’s public website; listings are not seller endorsements.</p><div className="seller-grid">{visibleSellers.map(seller => <article className="seller-card" key={seller.name}><div className="seller-top"><div className="seller-mark" style={{ background: seller.color }}>{seller.initials}</div><span className="pill">{seller.kind}</span></div><h3>{seller.name}</h3><span className="seller-country"><Globe2 size={12} /> {seller.country}</span><p>{seller.description}</p><div className="seller-categories">{seller.categories.slice(0, 3).map(c => <span key={c}>{c}</span>)}</div><div className="seller-links"><a href={seller.url} target="_blank" rel="noopener noreferrer">Explore source <ArrowUpRight size={15} /></a><a href={seller.contact} target="_blank" rel="noopener noreferrer" aria-label={`Contact ${seller.name}`}><ExternalLink size={15} /></a></div></article>)}</div>{!visibleSellers.length && <Empty title="No sources in this edit yet" text="Try a different search or seller type." action={() => { setQuery(""); setCategory("All discoveries"); setSellerKind("All sellers"); }} button="Reset filters" />}</> : results.length ? <><div className="product-grid">{results.map((product, i) => <article className="product-card" key={product.id}><div className="product-image-wrap"><button className="image-button" onClick={() => { setSelected(product); setCollectionName(saves.find(s => s.productId === product.id)?.collection ?? "My edit"); }} aria-label={`View ${product.name}`}><ProductImage product={product} /></button><span className={`product-badge ${product.sample ? "" : "imported-badge"}`}>{product.sample ? i % 3 === 0 ? "THE EVERYDAY EDIT" : product.category.toUpperCase() : "YOUR DISCOVERY"}</span><button className={`save-button ${savedIds.has(product.id) ? "is-saved" : ""}`} aria-label={savedIds.has(product.id) ? `Unsave ${product.name}` : `Save ${product.name}`} aria-pressed={savedIds.has(product.id)} disabled={saveBusy} onClick={() => toggleSave(product)}><Heart size={17} fill={savedIds.has(product.id) ? "currentColor" : "none"} /></button><button className={`compare-add ${comparison.includes(product.id) ? "is-compared" : ""}`} onClick={() => toggleCompare(product.id)} aria-pressed={comparison.includes(product.id)}>{comparison.includes(product.id) ? <Check size={13} /> : <Plus size={13} />} Compare</button></div><div className="product-info"><span className="product-brand">{product.brand}</span><button className="product-title" onClick={() => { setSelected(product); setCollectionName(saves.find(s => s.productId === product.id)?.collection ?? "My edit"); }}>{product.name}</button><p>{product.description}</p><div className="product-price"><strong>{priceLabel(lowestOffer(product))}</strong><span>{product.sample ? `${lowestOffer(product)?.currency ?? ""} · Sample` : `${product.offers.length} ${product.offers.length === 1 ? "offer" : "offers"}`}</span></div></div></article>)}</div>{results.some(p => p.sample) && <p className="sample-note"><Leaf size={13} /> An inspiration catalog: sample imagery, details, and prices are illustrative. Import a link to build your real catalog.</p>}</> : <Empty title={view === "My catalog" ? "Your next good find starts here" : view === "Collections" ? "Make room for your favorites" : "A different find is waiting"} text={view === "My catalog" ? "Paste a product link and we’ll gather the details into your personal catalog." : view === "Collections" ? "Tap the heart on any product to save it. Sign in to keep your edit across visits." : "Try a broader search, another category, or import a product you already love."} action={() => { if (view === "My catalog") openImport(); else { setQuery(""); setCategory("All discoveries"); setCurrency("All currencies"); setSampleVisible(true); if (view === "Collections") navigate("Discover"); } }} button={view === "My catalog" ? "Add your first product" : view === "Collections" ? "Explore discoveries" : "Reset your search"} />}

        {query && view !== "Sellers" && <div className="search-beyond"><div><span className="eyebrow">KEEP EXPLORING</span><h3>Take “{query}” a little further.</h3><p>Continue your search on these sources, then bring a supported product link back to Vastra.</p></div><div><a className="button button-outline" href={`https://www.google.com/search?tbm=shop&q=${encodeURIComponent(query)}`} target="_blank" rel="noopener noreferrer">Google Shopping <ArrowUpRight size={14} /></a><a className="button button-outline" href={`https://www.etsy.com/search?q=${encodeURIComponent(query)}`} target="_blank" rel="noopener noreferrer">Etsy <ArrowUpRight size={14} /></a></div></div>}
      </section>

      <section className="import-callout"><div className="callout-icon"><Link2 size={29} strokeWidth={1.3} /></div><div><span className="eyebrow">FOUND SOMETHING YOU LOVE?</span><h2>One link. All the lovely details.</h2><p>Bring a product into Vastra. We’ll gather its details and give it a place in your edit.</p></div><button className="button button-dark" onClick={() => openImport()}><Plus size={16} /> Add a product link <ArrowUpRight size={16} /></button></section>
    </main>

    <footer className="footer"><div><a href="/" className="brand footer-brand">vastra.</a><span>A considered way to discover.</span></div><p>Fashion. Beauty. A little possibility.</p><button onClick={() => setShowAbout(true)}>Made for the curious <Leaf size={13} /></button></footer>
    {notice && <div className="toast" role="status"><Check size={16} /><span>{notice}</span>{!user && <a href="/signin-with-chatgpt?return_to=/" target="_top">Sign in</a>}<button className="icon-button" aria-label="Dismiss notification" onClick={() => setNotice("")}><X size={15} /></button></div>}
    {comparison.length > 0 && !showCompare && <div className="compare-tray"><div><Layers3 size={18} /><span><strong>{comparison.length}</strong> {comparison.length === 1 ? "find" : "finds"} in your comparison</span></div><button className="button button-dark small" onClick={() => setShowCompare(true)}>Compare <ArrowRight size={15} /></button><button className="icon-button" aria-label="Clear comparison" onClick={() => setComparison([])}><X size={17} /></button></div>}

    {showImport && <Modal title="Add a product" close={() => { if (!importBusy) setShowImport(false); }}><div className="import-modal-content"><div className="modal-symbol"><Link2 size={26} /></div><h2>A link to your next good find.</h2><p>Paste a product page. We’ll gather the images, details, and available pricing into your catalog.</p><form onSubmit={importLink}><label htmlFor="product-url">Product link</label><input id="product-url" type="url" placeholder="https://www.store.com/product/…" value={importUrl} onChange={e => setImportUrl(e.target.value)} maxLength={2048} required disabled={importBusy} autoFocus />{importError && <div role="alert" className="form-error">{importError}</div>}<button type="submit" className="button button-dark full-width" disabled={importBusy || !user}>{importBusy ? <><Loader2 size={17} className="spin" /> Gathering product details…</> : <><Sparkles size={17} /> Import product</>}</button></form>{!user && <a className="button button-outline full-width sign-in-link" href="/signin-with-chatgpt?return_to=/" target="_top">Sign in with ChatGPT to import <ArrowUpRight size={15} /></a>}<div className="import-explainer"><span><Check size={13} /> Original store currency</span><span><Check size={13} /> Source-linked details</span><span><Check size={13} /> No AI key needed</span></div><details className="supported-stores"><summary>Supported stores & import limitations <ChevronDown size={14} /></summary><p>{supportedRetailers.filter(s => s !== "www2.hm.com").join(" · ")}</p><p>These domains are eligible for import. Extraction depends on each page’s public product data and may be blocked by the store. Shipping, duties, and returns must be confirmed with the seller. Unsupported stores are not fetched.</p></details></div></Modal>}

    {selected && <Modal title="A closer look" close={() => setSelected(null)} wide><div className="product-detail"><div className="detail-image"><ProductImage product={selected} /><span className="detail-image-caption">{selected.sample ? "Illustrative catalog photography" : "Image provided by the source store"}</span></div><div className="detail-copy"><span className="eyebrow">{selected.brand}</span><h2>{selected.name}</h2><p className="detail-description">{selected.description || "The store did not provide a description."}</p><div className="detail-tags"><span>{selected.category}</span>{selected.color && <span>{selected.color}</span>}</div><dl className="spec-list"><div><dt>Material / formulation</dt><dd>{selected.material ?? "Not provided by seller"}</dd></div><div><dt>Sizes listed</dt><dd>{selected.sizes.length ? selected.sizes.join(" · ") : "Check with seller"}</dd></div><div><dt>Shipping, taxes & duties</dt><dd>Not included — confirm at checkout</dd></div><div><dt>Quality evidence</dt><dd>{selected.sample ? "Illustrative details only" : "Seller-provided details; not independently verified"}</dd></div></dl><div className="offers-section"><h3>{selected.sample ? "An illustrative price" : "Offers from this source"}</h3>{selected.offers.map((offer, i) => <div className="offer-row" key={i}><div><strong>{priceLabel(offer)}</strong><span>{offer.seller} · {offer.availability}</span></div>{offer.url && <a className="icon-button" href={offer.url} target="_blank" rel="noopener noreferrer" aria-label={`View offer at ${offer.seller}`}><ArrowUpRight size={20} /></a>}</div>)}</div>{selected.sample ? <p className="detail-disclaimer">This is a sample product, not a live listing. Images, specifications, and prices are for inspiration.</p> : <p className="detail-disclaimer">Extracted {new Date(selected.checkedAt).toLocaleString()}. Prices and stock can change. {selected.extraction === "metadata" ? "Limited page metadata was available." : "Details extracted from structured product data."}</p>}<label className="collection-label" htmlFor="collection-name">Save to a collection</label><input id="collection-name" list="collection-options" value={collectionName} onChange={e => setCollectionName(e.target.value)} placeholder="My edit" maxLength={60} disabled={savedIds.has(selected.id)} /><datalist id="collection-options">{collections.map(c => <option value={c} key={c} />)}</datalist><div className="detail-actions"><button className="button button-dark" disabled={saveBusy} onClick={() => toggleSave(selected, collectionName.trim() || "My edit")}><Heart size={16} fill={savedIds.has(selected.id) ? "currentColor" : "none"} />{savedIds.has(selected.id) ? "Remove from collection" : "Save to my edit"}</button><button className="button button-outline" onClick={() => toggleCompare(selected.id)}>{comparison.includes(selected.id) ? <Check size={16} /> : <Plus size={16} />} Compare</button></div>{selected.sourceUrl && <div className="source-actions"><a href={selected.sourceUrl} target="_blank" rel="noopener noreferrer">View original product <ArrowUpRight size={14} /></a><button aria-label="Delete imported product" onClick={() => removeProduct(selected)}><Trash2 size={14} /> Remove</button></div>}</div></div></Modal>}

    {showCompare && <Modal title="Compare your finds" close={() => setShowCompare(false)} wide><div className="comparison-content"><h2>A little perspective.</h2><p>Compare details side by side. These are independently selected products, not verified exact matches. Prices exclude shipping, taxes, and duties.</p><div className="comparison-scroll"><table className="comparison-table"><thead><tr><th scope="col">A closer look</th>{compared.map(p => <th scope="col" key={p.id}><ProductImage product={p} /><span>{p.name}</span><button className="text-link" onClick={() => setComparison(current => current.filter(id => id !== p.id))}>Remove</button></th>)}</tr></thead><tbody>{([ ["Price", (p: Product) => priceLabel(lowestOffer(p))], ["Currency", (p: Product) => [...new Set(p.offers.map(o => o.currency ?? "Unknown"))].join(", ")], ["Category", (p: Product) => p.category], ["Material", (p: Product) => p.material ?? "Not provided"], ["Color / size", (p: Product) => p.color ?? "Not provided"], ["Evidence", (p: Product) => p.sample ? "Sample data" : "Seller-provided"], ["Last checked", (p: Product) => p.sample ? "Illustrative" : new Date(p.checkedAt).toLocaleDateString()] ] as [string, (p: Product) => string][]).map(([label, get]) => <tr key={label}><th scope="row">{label}</th>{compared.map(p => <td key={p.id}>{get(p)}</td>)}</tr>)}</tbody></table></div>{compared.length === 0 && <p>Add products using the Compare button on a product card.</p>}<p className="detail-disclaimer">Different currencies are shown as listed. Vastra does not convert currencies or declare a cheapest product across currencies.</p></div></Modal>}

    {showAbout && <Modal title="About Vastra" close={() => setShowAbout(false)}><div className="about-content"><span className="modal-symbol"><Leaf size={27} /></span><h2>For the joy of a good find.</h2><p>Vastra brings fashion, footwear, accessories, beauty, fragrance, and body care into one considered space.</p><h3>Your catalog, from a link</h3><p>Import from eligible stores, search your catalog, save named collections, and compare details in the original store currencies. Your imported products and saved collections belong to your signed-in account.</p><h3>A global beginning</h3><p>This first release searches the sample catalog and your imports. The seller directory and external search links help you explore further. Automatic live search across stores, exact-product matching, delivered-price calculations, and AI model connections are the next stages.</p><h3>Details with a source</h3><p>Imported data comes from the seller’s public page. Missing facts stay unknown. Sample products are always labeled. Quality claims, contacts, stock, returns, and final costs should be checked with the source.</p><a href="https://github.com/sudharamachandranrajeev/vastra" target="_blank" rel="noopener noreferrer" className="button button-outline">Explore the public repository <ArrowUpRight size={15} /></a></div></Modal>}
  </div>;
}

function Empty({ title, text, action, button }: { title: string; text: string; action: () => void; button: string }) {
  return <div className="empty-state"><Compass size={34} strokeWidth={1.2} /><h3>{title}</h3><p>{text}</p><button className="button button-dark" onClick={action}>{button} <ArrowRight size={15} /></button></div>;
}
