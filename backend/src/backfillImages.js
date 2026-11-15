// ══════════════════════════════════════════════════════════════
// Vendra Backend - Product photo backfill
//
//   npm run images:backfill              fill in missing photos
//   npm run images:backfill -- --dry-run show what would change
//
// 1. Products without a cover photo (e.g. added without one, or whose
//    download failed during seeding) get the best-matching catalogue photo:
//    most words in common with the product name, same category preferred.
// 2. Catalogue products (cover from the demo catalogue) with no gallery yet
//    get that product's other photos as their gallery.
// Photos come from the same DummyJSON catalogue the seed uses (cached in
// backend/.cache/) and go into the configured file storage. Safe to rerun:
// products that already have photos are left alone.
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const fs = require('fs');
const { Client } = require('pg');
const { loadCatalog } = require('./demoData/catalog');

const STOP_WORDS = new Set(['the', 'and', 'for', 'with', 'pack', 'new', 'set', 'of', 'in']);
const words = (text) => new Set(String(text || '').toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length >= 3 && !STOP_WORDS.has(w)));

/** Best catalogue item for a product: shared words first, then category, then a stable pick */
function bestMatch(product, catalog) {
  const mine = words(product.name);
  let best = null;
  let bestScore = 0;
  for (const item of catalog) {
    if (!item.imageFile) continue;
    const theirs = words(`${item.title} ${item.brand || ''}`);
    let score = 0;
    for (const w of mine) if (theirs.has(w)) score += 2;
    if (score > 0 && item.categoryId === product.category_id) score += 1;
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  if (best) return { item: best, how: 'name' };
  const sameCategory = catalog.filter((i) => i.imageFile && i.categoryId === product.category_id);
  const pool = sameCategory.length ? sameCategory : catalog.filter((i) => i.imageFile);
  return pool.length ? { item: pool[product.id % pool.length], how: sameCategory.length ? 'category' : 'any' } : null;
}

const coverName = (item) => `catalog-${item.key}.webp`;
const extraName = (item, n) => `catalog-${item.key}-${n + 2}.webp`;
const urlOf = (name) => `/uploads/products/${name}`;

async function backfill({ dryRun = false, log = console.log } = {}) {
  const { storageDriver, initStorage } = require('./services/storage.service');
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const catalog = await loadCatalog({ log });
    const byKey = new Map(catalog.map((i) => [i.key, i]));
    const where = dryRun ? 'nowhere (dry run)' : await initStorage();
    const stored = new Set();
    const store = async (name, file) => {
      if (dryRun || stored.has(name)) return;
      await storageDriver.save('products', name, fs.readFileSync(file), 'image/webp');
      stored.add(name);
    };

    // 1. Missing covers
    const missing = (await client.query(
      'SELECT id, name, category_id FROM products WHERE is_active AND image_url IS NULL ORDER BY id'
    )).rows;
    const tally = { name: 0, category: 0, any: 0 };
    let covers = 0;
    for (const p of missing) {
      const match = bestMatch(p, catalog);
      if (!match) continue;
      tally[match.how]++;
      await store(coverName(match.item), match.item.imageFile);
      if (!dryRun) {
        await client.query('UPDATE products SET image_url = $1, updated_at = NOW() WHERE id = $2 AND image_url IS NULL', [urlOf(coverName(match.item)), p.id]);
      }
      covers++;
      if (dryRun) log(`  #${p.id} "${p.name}" ← ${match.item.title} (${match.how})`);
    }

    // 2. Galleries for catalogue products that have none
    const noGallery = (await client.query(
      `SELECT p.id, p.image_url FROM products p
       WHERE p.is_active AND p.image_url LIKE '/uploads/products/catalog-%'
         AND NOT EXISTS (SELECT 1 FROM product_images pi WHERE pi.product_id = p.id)
       ORDER BY p.id`
    )).rows;
    let galleries = 0;
    let photos = 0;
    for (const p of noGallery) {
      const key = p.image_url.replace('/uploads/products/catalog-', '').replace(/(-\d+)?\.webp$/, '');
      const item = byKey.get(key);
      if (!item || item.extraImageFiles.length === 0) continue;
      for (const [n, file] of item.extraImageFiles.entries()) {
        await store(extraName(item, n), file);
        if (!dryRun) {
          await client.query('INSERT INTO product_images (product_id, url, position) VALUES ($1, $2, $3)', [p.id, urlOf(extraName(item, n)), n]);
        }
        photos++;
      }
      galleries++;
    }

    log(`✓ ${covers} product(s) got a cover photo (${tally.name} by name, ${tally.category} by category, ${tally.any} any)`);
    log(`✓ ${galleries} product(s) got a gallery (${photos} photos)`);
    log(`  Files in ${where}`);
    return { covers, galleries, photos };
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  backfill({ dryRun: process.argv.includes('--dry-run') }).catch((err) => {
    console.error('✗ Photo backfill failed:', err.message);
    process.exit(1);
  });
}

module.exports = { backfill, bestMatch };
