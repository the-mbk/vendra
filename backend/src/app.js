// ══════════════════════════════════════════════════════════════
// Vendra Backend - App factory
// Builds the Express app + HTTP server + Socket.IO without listening,
// so server.js and the tests share the same wiring.
// ══════════════════════════════════════════════════════════════

const http = require('http');
const express = require('express');
const cors = require('cors');

const { corsOrigin } = require('./utils/cors');
const { initRealtime } = require('./realtime');
const { PRODUCTS_DIR, PRODUCTS_PUBLIC_PATH, resolveSignedEvidence } = require('./services/storage.service');

const authRoutes = require('./routes/auth.routes');
const vendorRoutes = require('./routes/vendor.routes');
const customerRoutes = require('./routes/customer.routes');
const riderRoutes = require('./routes/rider.routes');
const accountRoutes = require('./routes/account.routes');
const adminRoutes = require('./routes/admin.routes');

function createServer({ logRequests = true } = {}) {
  const app = express();

  // CORS — localhost in dev (Flutter web uses random ports) + ALLOWED_ORIGINS
  app.use(cors({
    origin: corsOrigin,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
  }));
  app.use(express.json());

  if (logRequests) {
    app.use((req, res, next) => {
      console.log(`${new Date().toISOString()} | ${req.method} ${req.url}`);
      next();
    });
  }

  // Product photos are public; dispute evidence only through signed, expiring links
  app.use(PRODUCTS_PUBLIC_PATH, express.static(PRODUCTS_DIR, { maxAge: '7d', index: false }));
  app.get('/api/files/evidence/:name', (req, res) => {
    const file = resolveSignedEvidence(req.params.name, req.query.exp, req.query.sig);
    if (!file) return res.status(403).json({ success: false, message: 'This link is invalid or has expired.' });
    res.set('Cache-Control', 'private, max-age=600');
    res.sendFile(file);
  });

  // Routes
  app.use('/api/auth', authRoutes);
  app.use('/api/vendor', vendorRoutes);
  app.use('/api/rider', riderRoutes);
  app.use('/api/admin', adminRoutes);
  app.use('/api', customerRoutes);
  app.use('/api', accountRoutes);

  app.get('/api/health', (req, res) => {
    res.json({ success: true, message: 'Vendra API is running 🚀', timestamp: new Date().toISOString() });
  });

  // 404 handler
  app.use((req, res) => {
    res.status(404).json({ success: false, message: 'Route not found' });
  });

  // Global error handler — typed errors (httpError) keep their status and details
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err.statusCode) {
      return res.status(err.statusCode).json({ success: false, message: err.message, ...err.details });
    }
    if (err.name === 'MulterError') {
      const message = err.code === 'LIMIT_FILE_SIZE' ? 'Each photo must be 5 MB or smaller.'
        : err.code === 'LIMIT_FILE_COUNT' || err.code === 'LIMIT_UNEXPECTED_FILE' ? 'Attach up to 4 photos in the "evidence" field.'
        : err.message;
      return res.status(400).json({ success: false, message });
    }
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ success: false, message: 'Request body is not valid JSON.' });
    }
    if (err.code === 'ESCROW_POOL_UNDERFLOW') {
      console.error('🔥 Escrow pool underflow:', err.stack);
      return res.status(409).json({ success: false, message: 'Escrow pool out of sync. Contact support.' });
    }
    if (err.message === 'Not allowed by CORS') {
      return res.status(403).json({ success: false, message: 'Origin not allowed.' });
    }
    console.error('🔥 Unhandled Error:', err.stack);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
      ...(process.env.NODE_ENV === 'development' && { error: err.message }),
    });
  });

  const server = http.createServer(app);
  initRealtime(server);
  return { app, server };
}

module.exports = { createServer };
