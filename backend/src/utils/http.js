// ══════════════════════════════════════════════════════════════
// HTTP helpers — typed errors, async route wrapper, transactions
// ══════════════════════════════════════════════════════════════

const pool = require('../db');

/** Error the global handler turns into { success:false, message, ...details } */
function httpError(statusCode, message, details = {}) {
  const err = new Error(message);
  err.statusCode = statusCode;
  err.details = details;
  return err;
}

/** Wraps an async route so thrown errors reach the global error handler */
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/**
 * Runs fn(client, afterCommit) inside BEGIN/COMMIT.
 * afterCommit is an array of callbacks (socket emits) run only once the commit succeeds,
 * so clients are never told about changes that were rolled back.
 */
async function withTransaction(fn) {
  const client = await pool.connect();
  const afterCommit = [];
  try {
    await client.query('BEGIN');
    const result = await fn(client, afterCommit);
    await client.query('COMMIT');
    for (const cb of afterCommit) {
      try { cb(); } catch (e) { console.error('afterCommit callback failed:', e); }
    }
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** Parses a positive integer route param or throws 400 */
function intParam(value, name = 'id') {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw httpError(400, `Invalid ${name}.`);
  return n;
}

/**
 * ?limit=&offset= → { limit, offset }. Query with LIMIT limit + 1 and pass the rows
 * to pageOf() so the client learns whether more exist without a COUNT(*).
 */
function paging(query, { defaultLimit = 20, maxLimit = 100 } = {}) {
  const limit = Math.min(Math.max(parseInt(query.limit, 10) || defaultLimit, 1), maxLimit);
  const offset = Math.max(parseInt(query.offset, 10) || 0, 0);
  return { limit, offset };
}

/** Trims the extra look-ahead row and builds the meta block */
function pageOf(rows, { limit, offset }) {
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  return { items, meta: { limit, offset, hasMore, nextOffset: hasMore ? offset + limit : null } };
}

module.exports = { httpError, asyncHandler, withTransaction, intParam, paging, pageOf };
