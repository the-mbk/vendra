// ══════════════════════════════════════════════════════════════
// Vendra Backend - Seed Runner
// Loads seed.sql into a freshly migrated database (no psql needed).
// Usage: npm run migrate && npm run seed
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

async function seed(connectionString = process.env.DATABASE_URL) {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const existing = await client.query('SELECT COUNT(*) FROM users');
    if (Number(existing.rows[0].count) > 0) {
      throw new Error('Database already has users. Seed only runs on an empty, freshly migrated database.');
    }
    await client.query(fs.readFileSync(path.join(__dirname, '..', 'seed.sql'), 'utf8'));
    console.log('✓ Seed data loaded. All demo accounts use password123.');
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  seed().catch((err) => {
    console.error('✗ Seed failed:', err.message);
    process.exit(1);
  });
}

module.exports = { seed };
