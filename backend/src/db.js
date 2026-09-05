// ══════════════════════════════════════════════════════════════
// Vendra Backend - Database Connection Pool
// Uses PostgreSQL via 'pg' library with connection pooling
// ══════════════════════════════════════════════════════════════

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // Connection pool settings for optimal performance
  max: 20,                  // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30s
  connectionTimeoutMillis: 2000, // Timeout after 2s if can't connect
});

// Log connection status
pool.on('connect', () => {
  console.log('📦 Connected to PostgreSQL database');
});

pool.on('error', (err) => {
  console.error('❌ Unexpected database error:', err);
  process.exit(-1);
});

module.exports = pool;
