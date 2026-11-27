#!/usr/bin/env node

/**
 * Fast, token-efficient Chrome CDP e-commerce search and product inspector.
 * Connects to local Chrome on http://127.0.0.1:9222 if running, otherwise
 * automatically uses WrapVM shared Chrome on prox (http://10.0.2.100:9223).
 */

import { parseArgs } from "node:util";

const DEFAULT_LOCAL_CDP = "http://127.0.0.1:9222";
const DEFAULT_WRAPVM_CDP = "http://10.0.2.100:9223";
let resolvedCdpBase = null;

async function resolveCdpBase() {
  if (resolvedCdpBase) return resolvedCdpBase;
  if (process.env.CHROME_CDP_URL) {
    resolvedCdpBase = process.env.CHROME_CDP_URL;
    return resolvedCdpBase;
  }
  try {
    const res = await fetch(`${DEFAULT_LOCAL_CDP}/json/version`, {
      signal: AbortSignal.timeout(400),
    });
    if (res.ok) {
      resolvedCdpBase = DEFAULT_LOCAL_CDP;
      return resolvedCdpBase;
    }
  } catch {
    // Local debug Chrome not running; fall back to WrapVM on prox
  }
  resolvedCdpBase = DEFAULT_WRAPVM_CDP;
  return resolvedCdpBase;
}

async function getChromeTabs() {
  const cdpBase = await resolveCdpBase();
  try {
    const res = await fetch(`${cdpBase}/json`, {
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    throw new Error(
      `Cannot connect to Chrome CDP at ${cdpBase} (local 127.0.0.1:9222 and WrapVM 10.0.2.100:9223). (${err.message})`
    );
  }
}

async function getOrCreateTab(domainMatch, targetUrl) {
  const cdpBase = await resolveCdpBase();
  const tabs = await getChromeTabs();
  let tab = tabs.find(
    (t) => t.type === "page" && t.url && t.url.includes(domainMatch)
  );

  if (!tab) {
    const newTabRes = await fetch(`${cdpBase}/json/new?${encodeURIComponent(targetUrl)}`, {
      method: "PUT",
    });
    tab = await newTabRes.json();
  }
  return tab;
}

function connectCdp(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let idCounter = 1;
    const pending = new Map();

    ws.onopen = () => resolve({ ws, send });
    ws.onerror = (e) => reject(new Error(`WebSocket connection failed: ${e.message || e}`));

    ws.onmessage = (evt) => {
      try {
        const msg = JSON.parse(evt.data);
        if (msg.id && pending.has(msg.id)) {
          const { resolveReq, rejectReq } = pending.get(msg.id);
          pending.delete(msg.id);
          if (msg.error) {
            rejectReq(new Error(msg.error.message || JSON.stringify(msg.error)));
          } else {
            resolveReq(msg.result);
          }
        }
      } catch (err) {
        // ignore parse error
      }
    };

    function send(method, params = {}) {
      return new Promise((resolveReq, rejectReq) => {
        const id = idCounter++;
        pending.set(id, { resolveReq, rejectReq });
        ws.send(JSON.stringify({ id, method, params }));
      });
    }
  });
}

// Extractors for search listing pages
const LISTING_EXTRACTORS = {
  allegro: function() {
    return Array.from(document.querySelectorAll("article, [data-component-type='s-search-result']")).map(a => {
      const heading = a.querySelector("h2");
      const title = heading ? heading.innerText.trim() : (a.querySelector("a")?.innerText.trim() || "");
      const priceMatch = a.innerText.match(/\d+[\d\s]*,?\d*\s*zł/);
      const price = priceMatch ? priceMatch[0].replace(/\s+/g, " ") : "";
      const link = a.querySelector("h2 a, a[href*='/oferta/'], a[href*='/produkt/']");
      let href = link ? link.href : "";
      if (href.includes("redirect=")) {
        try {
          const u = new URL(href);
          href = decodeURIComponent(u.searchParams.get("redirect") || href).split("?")[0];
        } catch(e) {}
      } else if (href) {
        href = href.split("?")[0];
      }
      return { title, price, href };
    }).filter(x => x.title && x.href && x.price);
  },
  amazon: function() {
    return Array.from(document.querySelectorAll("div[data-asin]"))
      .filter(d => d.getAttribute("data-asin"))
      .map(d => {
        const asin = d.getAttribute("data-asin");
        const h2 = d.querySelector("h2");
        const title = h2 ? h2.innerText.trim() : "";
        const priceElem = d.querySelector(".a-price .a-offscreen, .a-price");
        let price = "";
        if (priceElem) {
          price = priceElem.innerText.split("\n")[0].replace(/\s+/g, " ").trim();
        }
        const href = asin ? ("https://www.amazon.pl/dp/" + asin) : "";
        return { title, price, href, asin };
      })
      .filter(x => x.title && x.href);
  },
  ceneo: function() {
    return Array.from(document.querySelectorAll(".cat-prod-row, .grid-row, .js_category-list-item")).map(el => {
      const titleElem = el.querySelector(".cat-prod-row__name, .grid-item__name, a[title]");
      const title = titleElem ? (titleElem.getAttribute("title") || titleElem.innerText.trim()) : "";
      const priceElem = el.querySelector(".price .value, .price");
      const pricePenny = el.querySelector(".price .penny")?.innerText || "";
      let price = priceElem ? priceElem.innerText.trim() : "";
      if (pricePenny && !price.includes(pricePenny)) price += pricePenny + " zł";
      const link = el.querySelector("a.js_search-rubric, a.cat-prod-row__name, a[href*='/']");
      let href = link ? link.href : "";
      if (href && !href.startsWith("http")) href = "https://www.ceneo.pl" + href;
      return { title, price, href: href.split("#")[0] };
    }).filter(x => x.title && x.href);
  },
  olx: function() {
    return Array.from(document.querySelectorAll("[data-cy='l-card'], [data-testid='l-card']")).map(c => {
      const titleEl = c.querySelector("h4, h6, [data-testid='ad-card-title']");
      const title = titleEl ? titleEl.innerText.split("\n")[0].trim() : "";
      const priceEl = c.querySelector("[data-testid='ad-price']");
      const price = priceEl ? priceEl.innerText.replace(/\s+/g, " ").trim() : "";
      const locEl = c.querySelector("[data-testid='location-date']");
      const location = locEl ? locEl.innerText.replace(/\s+/g, " ").trim() : "";
      const olxDelivery = Boolean(
        c.querySelector("[data-testid='card-delivery-badge'], [data-testid='free-delivery-tag']")
      );
      const link = c.querySelector("a[href*='/d/oferta/'], a[href]");
      let href = link ? link.href : "";
      if (href) href = href.split("?")[0];
      return { title, price, location, olxDelivery, href };
    }).filter(x => x.title && x.href && x.price);
  }
};

// Extractor for a specific single product/offer page
function extractProductDetails() {
  const url = window.location.href;
  const isAllegro = url.includes("allegro.pl");
  const isAmazon = url.includes("amazon.");
  const isOlx = url.includes("olx.pl");

  if (isOlx) {
    const rawTitle = document.querySelector("[data-testid='offer_title'] h4, [data-cy='ad_title'] h4")?.innerText?.trim()
      || document.title.replace(/\s*[•|-]\s*OLX\.pl.*$/i, "").trim();
    const price = document.querySelector("[data-testid='ad-price-container']")?.innerText?.replace(/\s+/g, " ")?.trim() || "";
    const seller = document.querySelector("[data-testid='user-profile-user-name']")?.innerText?.trim() || "";
    const locRaw = document.querySelector("[data-testid='map-aside-section']")?.innerText?.replace(/\s+/g, " ")?.replace(/^LOKALIZACJA\s*/i, "")?.trim() || "";
    const olxDelivery = Boolean(document.querySelector("[data-testid*='delivery' i], [data-testid*='shipping' i], [data-testid='buy-with-delivery-btn'], button[data-testid*='buy' i]"));
    const params = {};
    if (locRaw) params["Lokalizacja"] = locRaw;
    params["Przesyłka OLX"] = olxDelivery ? "TAK" : "brak / sprawdź";
    document.querySelectorAll("[data-testid='ad-parameters-container'] p").forEach((p, idx) => {
      const txt = p.innerText.trim();
      if (!txt) return;
      if (txt.includes(":")) {
        const [k, ...rest] = txt.split(":");
        params[k.trim()] = rest.join(":").trim();
      } else {
        params[`Typ_${idx + 1}`] = txt;
      }
    });
    const descEl = document.querySelector("[data-testid='ad_description']");
    const description = descEl ? descEl.innerText.replace(/^Opis\s*\n+/i, "").replace(/\n{3,}/g, "\n\n").trim() : "";
    return {
      type: "product_details",
      platform: "olx",
      url: url.split("?")[0],
      title: rawTitle,
      price,
      seller,
      parameters: params,
      description
    };
  }

  if (isAllegro) {
    const title = document.querySelector("h1")?.innerText.trim() || document.title;
    let ldPrice = "";
    for (const s of document.querySelectorAll("script[type='application/ld+json']")) {
      try {
        const j = JSON.parse(s.textContent);
        const nodes = Array.isArray(j) ? j : (j["@graph"] || [j]);
        for (const n of nodes) {
          const p = n?.offers?.price || n?.offers?.lowPrice || (Array.isArray(n?.offers) && n.offers[0]?.price);
          if (p) { ldPrice = String(p).replace(".", ",") + " zł"; break; }
        }
        if (ldPrice) break;
      } catch {}
    }
    const metaPrice = document.querySelector("meta[itemprop='price'], meta[property='product:price:amount']")?.getAttribute("content");
    const priceElem = document.querySelector("[data-box-name*='price' i], [aria-label^='cena' i]");
    let price = ldPrice;
    if (!price && metaPrice) {
      price = metaPrice.replace(".", ",") + " zł";
    } else if (!price && priceElem) {
      const m = priceElem.innerText.match(/\d+[\d\s]*,?\d*\s*zł/);
      price = m ? m[0].replace(/\s+/g, " ").trim() : priceElem.innerText.split("\n")[0].replace(/\s+/g, " ").trim();
      if (price && !price.includes("zł")) price += " zł";
    }

    const params = {};
    const paramBox = document.querySelector("[data-box-name='Parameters'], [data-prototype-id*='parameters']");
    if (paramBox) {
      const lines = paramBox.innerText.split("\n").map(s => s.trim()).filter(Boolean);
      for (let i = 0; i < lines.length - 1; i += 2) {
        if (lines[i].length < 80 && lines[i + 1].length < 150) {
          params[lines[i]] = lines[i + 1];
        }
      }
    }

    const descEl = document.querySelector("[data-box-name*='Description'], section[data-box-name='standardizedDescription']");
    const description = descEl ? descEl.innerText.replace(/\n{3,}/g, "\n\n").trim() : "";

    const seller = document.querySelector("[data-box-name*='Seller'] a, a[href*='/uzytkownik/']")?.innerText.split("\n")[0].trim() || "";

    return {
      type: "product_details",
      platform: "allegro",
      url: url.split("?")[0],
      title,
      price,
      seller,
      parameters: params,
      description
    };
  }

  if (isAmazon) {
    const title = document.querySelector("#productTitle")?.innerText.trim() || document.title;
    const priceElem = document.querySelector(".a-price .a-offscreen, #corePrice_feature_div .a-offscreen");
    const price = priceElem ? priceElem.innerText.replace(/\s+/g, " ").trim() : "";

    const bullets = Array.from(document.querySelectorAll("#feature-bullets li span.a-list-item"))
      .map(s => s.innerText.trim())
      .filter(Boolean);

    const params = {};
    document.querySelectorAll("#productDetails_techSpec_section_1 tr, #detailBullets_feature_div li").forEach(row => {
      const k = row.querySelector("th, span.a-text-bold")?.innerText.replace(/:|\n/g, "").trim();
      const v = row.querySelector("td, span:not(.a-text-bold)")?.innerText.trim();
      if (k && v && k.length < 80) params[k] = v;
    });

    const descEl = document.querySelector("#productDescription, #aplus");
    const description = (descEl ? descEl.innerText.replace(/\n{3,}/g, "\n\n").trim() : "") || bullets.join("\n\n");

    return {
      type: "product_details",
      platform: "amazon",
      url: url.split("?")[0],
      title,
      price,
      parameters: params,
      bullets,
      description
    };
  }

  // Generic fallback for any other site
  return {
    type: "product_details",
    platform: "generic",
    url,
    title: document.querySelector("h1")?.innerText.trim() || document.title,
    description: (document.querySelector("article, main, .product-description, .description") || document.body)?.innerText.slice(0, 3000)
  };
}

async function main() {
  const { values } = parseArgs({
    options: {
      site: { type: "string", short: "s", default: "allegro" },
      query: { type: "string", short: "q" },
      url: { type: "string", short: "u" },
      details: { type: "string", short: "d" },
      limit: { type: "string", short: "l", default: "10" },
      format: { type: "string", short: "f", default: "markdown" },
      wait: { type: "string", short: "w", default: "2500" },
      courier: { type: "boolean", default: false },
      city: { type: "string", default: "" },
      category: { type: "string", default: "" }
    },
    allowPositionals: true
  });

  const query = values.query || "";
  const detailsUrl = values.details || values.url;
  const isDetailsMode = Boolean(values.details || (values.url && (values.url.includes("/oferta/") || values.url.includes("/d/oferta/") || values.url.includes("/produkt/") || values.url.includes("/dp/"))));
  const maxLimit = parseInt(values.limit, 10) || 10;
  const waitMs = parseInt(values.wait, 10) || 2500;
  let site = values.site.toLowerCase();

  let targetUrl = detailsUrl;
  let domainMatch = "allegro.pl";

  if (isDetailsMode && targetUrl) {
    try {
      domainMatch = new URL(targetUrl).hostname;
    } catch(e) {}
  } else if (!targetUrl) {
    if (!query) {
      console.error(JSON.stringify({ error: "Either --query or --url/--details must be provided" }));
      process.exit(1);
    }
    const enc = encodeURIComponent(query);
    if (site === "allegro") {
      targetUrl = `https://allegro.pl/listing?string=${enc}`;
      domainMatch = "allegro.pl";
    } else if (site === "amazon") {
      targetUrl = `https://www.amazon.pl/s?k=${enc}`;
      domainMatch = "amazon.pl";
    } else if (site === "ceneo") {
      targetUrl = `https://www.ceneo.pl/;szukaj-${enc}`;
      domainMatch = "ceneo.pl";
    } else if (site === "olx") {
      const slug = encodeURIComponent(query.trim().replace(/\s+/g, "-"));
      const cat = values.category ? values.category.replace(/^\/+|\/+$/g, "") : "";
      const city = values.city ? values.city.replace(/^\/+|\/+$/g, "").toLowerCase() : "";
      let prefix = "/oferty";
      if (cat && city) prefix = `/${cat}/${city}`;
      else if (cat) prefix = `/${cat}`;
      else if (city) prefix = `/${city}`;
      const qs = values.courier ? "?search%5Bcourier%5D=1" : "";
      targetUrl = `https://www.olx.pl${prefix}/q-${slug}/${qs}`;
      domainMatch = "olx.pl";
    } else {
      console.error(JSON.stringify({ error: `Unsupported site: ${site}. Use --url directly.` }));
      process.exit(1);
    }
  } else {
    try {
      domainMatch = new URL(targetUrl).hostname;
    } catch(e) {}
  }

  const tab = await getOrCreateTab(domainMatch, targetUrl);
  const { ws, send } = await connectCdp(tab.webSocketDebuggerUrl);

  try {
    await send("Page.enable");
    await send("Page.navigate", { url: targetUrl });
    await new Promise((r) => setTimeout(r, waitMs));

    if (isDetailsMode) {
      // Single product details mode
      const evalRes = await send("Runtime.evaluate", {
        expression: `(${extractProductDetails.toString()})()`,
        returnByValue: true
      });

      const details = evalRes?.result?.value || {};

      if (values.format === "json") {
        console.log(JSON.stringify({ success: true, details }, null, 2));
      } else {
        console.log(`### 📦 ${details.title || "Szczegóły oferty"}\n`);
        if (details.price) console.log(`- **Cena:** ${details.price}`);
        if (details.seller) console.log(`- **Sprzedawca:** ${details.seller}`);
        console.log(`- **Link:** [Otwórz aukcję](${details.url || targetUrl})\n`);

        const pKeys = Object.keys(details.parameters || {});
        if (pKeys.length > 0) {
          console.log(`#### ⚙️ Parametry techniczne:`);
          pKeys.forEach(k => console.log(`- **${k}:** ${details.parameters[k]}`));
          console.log("");
        }

        if (details.description) {
          console.log(`#### 📝 Opis przedmiotu:`);
          // Trim description if too long to maintain lean context
          const cleanDesc = details.description.slice(0, 3000);
          console.log(cleanDesc);
          if (details.description.length > 3000) {
            console.log("\n*(...opis skrócony do pierwszych 3000 znaków...)*");
          }
        }
      }
      return;
    }

    // Listing search mode
    const extractorFn = LISTING_EXTRACTORS[site] || LISTING_EXTRACTORS.allegro;
    const evalRes = await send("Runtime.evaluate", {
      expression: `(${extractorFn.toString()})()`,
      returnByValue: true
    });

    let items = (evalRes?.result?.value || []).slice(0, maxLimit);

    // Deduplicate by href
    const seen = new Set();
    items = items.filter(item => {
      if (!item.href || seen.has(item.href)) return false;
      seen.add(item.href);
      return true;
    });

    if (values.format === "json") {
      console.log(JSON.stringify({
        success: true,
        site,
        query: query || null,
        url: targetUrl,
        count: items.length,
        items
      }, null, 2));
    } else {
      if (items.length === 0) {
        console.log(`Brak ofert dla zapytania: "${query || targetUrl}".`);
      } else if (site === "olx") {
        console.log(`| Lp. | Produkt | Cena | Lokalizacja / Data | Przesyłka OLX | Link bezpośredni |`);
        console.log(`| :--- | :--- | :--- | :--- | :--- | :--- |`);
        items.forEach((it, idx) => {
          console.log(`| ${idx + 1} | ${it.title.replace(/\|/g, "-")} | **${it.price}** | ${it.location || "-"} | ${it.olxDelivery ? "✅ TAK" : "—"} | [Zobacz ofertę](${it.href}) |`);
        });
      } else {
        console.log(`| Lp. | Produkt | Cena | Link bezpośredni |`);
        console.log(`| :--- | :--- | :--- | :--- |`);
        items.forEach((it, idx) => {
          console.log(`| ${idx + 1} | ${it.title.replace(/\|/g, "-")} | **${it.price}** | [Zobacz ofertę](${it.href}) |`);
        });
      }
    }
  } finally {
    ws.close();
  }
}

main().catch((err) => {
  console.error(JSON.stringify({ success: false, error: err.message }));
  process.exit(1);
});
