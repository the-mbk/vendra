// ══════════════════════════════════════════════════════════════
// Vendra Backend - Express Server Entry Point
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const express = require('express');
const cors = require('cors');

// Import route modules
const authRoutes = require('./routes/auth.routes');
const vendorRoutes = require('./routes/vendor.routes');
const customerRoutes = require('./routes/customer.routes');
const adminRoutes = require('./routes/admin.routes');

const app = express();
const PORT = process.env.PORT || 3000;

// ──────────────────────────────────────
// Middleware
// ──────────────────────────────────────
// CORS Configuration — allow all localhost ports in dev (Flutter uses random ports)
app.use(cors({
  origin: function (origin, callback) {
    if (!origin || origin.includes('localhost') || origin.includes('127.0.0.1')) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.use(express.json());

// Request logging (dev)
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} | ${req.method} ${req.url}`);
  next();
});

// ──────────────────────────────────────
// Routes
// ──────────────────────────────────────
app.use('/api/auth', authRoutes);
app.use('/api/vendor', vendorRoutes);
app.use('/api', customerRoutes);
app.use('/api/admin', adminRoutes);

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ success: true, message: 'Vendra API is running 🚀', timestamp: new Date().toISOString() });
});

// ──────────────────────────────────────
// Global Error Handler
// ──────────────────────────────────────
app.use((err, req, res, next) => {
  console.error('🔥 Unhandled Error:', err.stack);
  res.status(500).json({
    success: false,
    message: 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { error: err.message }),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// ──────────────────────────────────────
// Start Server
// ──────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n══════════════════════════════════════`);
  console.log(`  🏪 Vendra API Server`);
  console.log(`  📍 Running on http://localhost:${PORT}`);
  console.log(`  🕐 Started at ${new Date().toLocaleString()}`);
  console.log(`══════════════════════════════════════\n`);
});

module.exports = app;
