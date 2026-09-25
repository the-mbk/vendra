// ══════════════════════════════════════════════════════════════
// Vendra Backend - Migration Runner
// Applies migrations/NNN_*.sql in order, once each, tracked in schema_migrations.
// Usage: npm run migrate
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');

async function migrate(connectionString = process.env.DATABASE_URL, { log = console.log } = {}) {
  const client = new Client({ connectionString });
  await client.connect();

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name VARCHAR(200) PRIMARY KEY,
        applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )`);

    const applied = new Set(
      (await client.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name)
    );

    const files = fs.readdirSync(MIGRATIONS_DIR)
      .filter((f) => /^\d{3}_.+\.sql$/.test(f))
      .sort();

    for (const file of files) {
      if (applied.has(file)) continue;

      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      log(`→ Applying ${file}`);

      // ALTER TYPE ... ADD VALUE cannot run inside a transaction block on older
      // Postgres, so each file runs as-is; files are written to be idempotent.
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    }

    log('✓ Database is up to date');
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  migrate().catch((err) => {
    console.error('✗ Migration failed:', err.message);
    process.exit(1);
  });
}

module.exports = { migrate };
