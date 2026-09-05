// ══════════════════════════════════════════════════════════════
// Vendra Backend - JWT Authentication Middleware
// Verifies JWT tokens and extracts user info for protected routes
// ══════════════════════════════════════════════════════════════

const jwt = require('jsonwebtoken');

/**
 * Main authentication middleware
 * Extracts and verifies JWT from Authorization header
 * Attaches user object { userId, role, vendorId } to req.user
 */
const authenticate = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Access denied. No token provided.',
      });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Attach decoded user info to request
    req.user = {
      userId: decoded.userId,
      role: decoded.role,
      vendorId: decoded.vendorId || null,
    };

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        success: false,
        message: 'Token expired. Please login again.',
      });
    }
    return res.status(401).json({
      success: false,
      message: 'Invalid token.',
    });
  }
};

/**
 * Role-based access control middleware factory
 * Usage: requireRole('vendor') or requireRole('customer', 'admin')
 */
const requireRole = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        message: 'Authentication required.',
      });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: `Access denied. Required role: ${roles.join(' or ')}.`,
      });
    }

    next();
  };
};

// Convenience middleware for specific roles
const requireVendor = requireRole('vendor');
const requireCustomer = requireRole('customer');
const requireAdmin = requireRole('admin');

module.exports = {
  authenticate,
  requireRole,
  requireVendor,
  requireCustomer,
  requireAdmin,
};
