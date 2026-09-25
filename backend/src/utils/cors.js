// ══════════════════════════════════════════════════════════════
// CORS origin check shared by Express and Socket.IO
// Allows localhost (any port) outside production, plus ALLOWED_ORIGINS.
// ══════════════════════════════════════════════════════════════

const LOCALHOST_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function allowedOrigins() {
  return (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
}

function isOriginAllowed(origin) {
  // Mobile apps and server-to-server calls send no Origin header
  if (!origin) return true;
  if (allowedOrigins().includes(origin)) return true;
  return process.env.NODE_ENV !== 'production' && LOCALHOST_ORIGIN.test(origin);
}

function corsOrigin(origin, callback) {
  if (isOriginAllowed(origin)) callback(null, true);
  else callback(new Error('Not allowed by CORS'));
}

module.exports = { corsOrigin, isOriginAllowed };
