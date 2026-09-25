// ══════════════════════════════════════════════════════════════
// Vendra Backend - Database Connection Pool
// Uses PostgreSQL via 'pg' library with connection pooling
// ══════════════════════════════════════════════════════════════

const { Pool } = require('pg');

// "Today" / "this week" in reports are counted in the marketplace's local time,
// whatever zone the database server itself runs in.
const APP_TIMEZONE = process.env.APP_TIMEZONE || 'Asia/Karachi';
if (!/^[A-Za-z_]+(\/[A-Za-z_+-]+)*$/.test(APP_TIMEZONE)) {
  throw new Error(`Invalid APP_TIMEZONE "${APP_TIMEZONE}"`);
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  options: `-c timezone=${APP_TIMEZONE}`,
  // Connection pool settings for optimal performance
  max: 20,                  // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30s
  connectionTimeoutMillis: 5000, // Timeout after 5s if can't connect
});

pool.on('error', (err) => {
  console.error('❌ Unexpected database error:', err);
  process.exit(-1);
});

module.exports = pool;
module.exports.APP_TIMEZONE = APP_TIMEZONE;
