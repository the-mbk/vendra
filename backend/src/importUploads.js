// ══════════════════════════════════════════════════════════════
// Copies photos saved on disk (backend/uploads, from before the S3 bucket)
// into the configured bucket. Safe to run more than once.
//   npm run storage:import
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const fs = require('fs');
const path = require('path');

const SAFE_NAME = /^[\w.-]+$/;

async function main() {
  const { storageDriver: driver, initStorage } = require('./services/storage.service');
  if (driver.name !== 's3') {
    console.log('S3_BUCKET is not set, so files already live on disk. Nothing to import.');
    return;
  }
  await initStorage();

  const root = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads'));
  // Evidence from before the evidence/ folder existed sits directly in uploads/
  const sources = [
    ['products', path.join(root, 'products')],
    ['evidence', path.join(root, 'evidence')],
    ['evidence', root],
  ];

  let copied = 0;
  let skipped = 0;
  for (const [kind, dir] of sources) {
    if (!fs.existsSync(dir)) continue;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isFile() || !SAFE_NAME.test(entry.name)) continue;
      const existing = await driver.open(kind, entry.name);
      if (existing) {
        existing.stream.destroy?.();
        skipped++;
        continue;
      }
      await driver.save(kind, entry.name, fs.readFileSync(path.join(dir, entry.name)));
      copied++;
    }
  }
  console.log(`Copied ${copied} file(s) into bucket "${driver.bucket}"; ${skipped} were already there.`);
}

main().catch((err) => {
  console.error('Import failed:', err.message);
  process.exit(1);
});
