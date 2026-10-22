// ══════════════════════════════════════════════════════════════
// Product catalogue for the demo dataset: names, descriptions, prices and
// photos from DummyJSON (https://dummyjson.com, a free fake-data API made
// for testing). Downloaded once and cached in backend/.cache/, so later
// seeds work offline. Prices are converted to rupees.
// ══════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');

const SOURCE = 'https://dummyjson.com/products?limit=0&select=title,description,price,category,brand,images,thumbnail';
const CACHE_DIR = path.join(__dirname, '..', '..', '.cache', 'demo-catalog');
const IMAGES_DIR = path.join(CACHE_DIR, 'images');
const LIST_FILE = path.join(CACHE_DIR, 'products.json');

const PKR_PER_USD = 280;

/** DummyJSON category → Vendra category id (see migration 004) */
const CATEGORY_IDS = {
  smartphones: 1, laptops: 1, tablets: 1,
  'mobile-accessories': 2,
  'mens-shirts': 3, 'mens-shoes': 3, 'mens-watches': 3, 'womens-bags': 3, 'womens-dresses': 3,
  'womens-jewellery': 3, 'womens-shoes': 3, 'womens-watches': 3, tops: 3, sunglasses: 3,
  groceries: 4,
  furniture: 5, 'home-decoration': 5, 'kitchen-accessories': 5,
  beauty: 6, fragrances: 6, 'skin-care': 6,
  'sports-accessories': 8,
};

/** Rupee price rounded the way shops price things */
function toRupees(usd) {
  const rs = usd * PKR_PER_USD;
  const step = rs < 1000 ? 10 : rs < 10000 ? 50 : 500;
  return Math.max(step, Math.round(rs / step) * step);
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);

async function fetchJson(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
  return res.json();
}

async function download(url, file) {
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

/**
 * @returns {Promise<Array<{ key, title, description, brand, group, categoryId, priceRs, imageFile|null }>>}
 */
async function loadCatalog({ log = console.log } = {}) {
  fs.mkdirSync(IMAGES_DIR, { recursive: true });

  let products;
  if (fs.existsSync(LIST_FILE)) {
    products = JSON.parse(fs.readFileSync(LIST_FILE, 'utf8'));
  } else {
    log('  Downloading the product catalogue from dummyjson.com…');
    products = (await fetchJson(SOURCE)).products;
    fs.writeFileSync(LIST_FILE, JSON.stringify(products));
  }

  const items = products
    .filter((p) => CATEGORY_IDS[p.category])
    .map((p) => ({
      key: slug(p.title),
      title: p.title,
      description: p.description,
      brand: p.brand || null,
      group: p.category,
      categoryId: CATEGORY_IDS[p.category],
      priceRs: toRupees(p.price),
      imageUrl: p.images?.[0] || p.thumbnail,
      imageFile: null,
    }));

  // Photos: the first full image of each product, a few downloads at a time
  const missing = items.filter((i) => i.imageUrl && !fs.existsSync(path.join(IMAGES_DIR, `${i.key}.webp`)));
  if (missing.length) log(`  Downloading ${missing.length} product photos…`);
  let failed = 0;
  for (let i = 0; i < missing.length; i += 8) {
    await Promise.all(missing.slice(i, i + 8).map((item) =>
      download(item.imageUrl, path.join(IMAGES_DIR, `${item.key}.webp`)).catch(() => { failed++; })));
  }
  if (failed) log(`  ${failed} photo(s) couldn't be downloaded; those products have no photo.`);

  for (const item of items) {
    const file = path.join(IMAGES_DIR, `${item.key}.webp`);
    if (fs.existsSync(file)) item.imageFile = file;
  }
  return items;
}

module.exports = { loadCatalog, CATEGORY_IDS };
