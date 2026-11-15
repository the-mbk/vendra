// ══════════════════════════════════════════════════════════════
// Security middleware (SSR 01): HTTP security headers + rate limits.
//   - helmet: nosniff, frame denial, HSTS, no X-Powered-By, referrer policy…
//     Product photos stay loadable from the apps' own origins (CORP cross-origin).
//   - API limit per IP (RATE_LIMIT_MAX requests per minute; default 300, or 2000 in
//     development, where every app on the machine shares 127.0.0.1)
//   - Login: 10 failed attempts per IP + email per 15 minutes, then 429.
//     Successful logins don't count, so a user who types correctly is never blocked.
//   - Signup: SIGNUP_RATE_LIMIT_MAX accounts per IP per hour (default 20)
// Staff PINs and delivery codes have their own per-account lockouts.
// Limits are kept in memory (one API process). Behind a proxy set TRUST_PROXY
// (e.g. 1) so the client's IP is used, not the proxy's.
// ══════════════════════════════════════════════════════════════

const helmet = require('helmet');
const { rateLimit } = require('express-rate-limit');
const { isDevelopment } = require('../config/mode');

const MINUTE = 60 * 1000;
const envInt = (name, fallback) => {
  const n = parseInt(process.env[name], 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
};

function tooMany(message, code) {
  return (req, res, _next, options) => {
    const retryAfter = Math.ceil(options.windowMs / 1000);
    res.status(429).json({ success: false, code, message, retryAfterSeconds: retryAfter });
  };
}

const securityHeaders = helmet({
  // The apps (Flutter web, admin dashboard) load product photos from this API
  crossOriginResourcePolicy: { policy: 'cross-origin' },
});

function createLimiters() {
  const api = rateLimit({
    windowMs: MINUTE,
    limit: envInt('RATE_LIMIT_MAX', isDevelopment ? 2000 : 300),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    // Gateway webhooks are signed and retried by the gateway itself
    skip: (req) => req.path === '/payments/webhook',
    handler: tooMany('Too many requests. Please slow down and try again in a minute.', 'RATE_LIMITED'),
  });

  const login = rateLimit({
    windowMs: 15 * MINUTE,
    limit: envInt('LOGIN_RATE_LIMIT_MAX', 10),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    keyGenerator: (req) => `${req.ip}|${String(req.body?.email || '').trim().toLowerCase()}`,
    handler: tooMany('Too many failed sign-in attempts. Try again in 15 minutes.', 'LOGIN_RATE_LIMITED'),
  });

  const signup = rateLimit({
    windowMs: 60 * MINUTE,
    limit: envInt('SIGNUP_RATE_LIMIT_MAX', 20),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: tooMany('Too many accounts created from this network. Try again later.', 'SIGNUP_RATE_LIMITED'),
  });

  return { api, login, signup };
}

/** Express "trust proxy" from TRUST_PROXY (hop count, or true/false) */
function trustProxySetting() {
  const v = process.env.TRUST_PROXY;
  if (!v) return false;
  if (v === 'true') return true;
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : v;
}

module.exports = { securityHeaders, createLimiters, trustProxySetting };
