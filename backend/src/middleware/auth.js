// ══════════════════════════════════════════════════════════════
// Vendra Backend - JWT Authentication Middleware
// Verifies JWT tokens and extracts user info for protected routes
//
// Shop staff (cashier, packer, inventory manager) sign in on the shop's
// device with a PIN and get a token carrying staffId + staffRole on top of
// the store owner's identity. Staff tokens are refused everywhere except
// routes mounted with authenticateAllowStaff, and those routes check
// requirePermission() — so a cashier can never reach the owner's wallet.
// ══════════════════════════════════════════════════════════════

const jwt = require('jsonwebtoken');
const pool = require('../db');

/** What each staff role may do. The store owner (no staff role) may do everything. */
const STAFF_PERMISSIONS = Object.freeze({
  cashier: ['products.view', 'pos'],
  packer: ['products.view', 'orders.view', 'orders.fulfil'],
  inventory_manager: ['products.view', 'products.manage', 'ledger', 'orders.view'],
});
const OWNER_PERMISSIONS = Object.freeze(['products.view', 'products.manage', 'pos', 'orders.view', 'orders.fulfil', 'ledger', 'owner']);

const permissionsOf = (staffRole) => (staffRole ? STAFF_PERMISSIONS[staffRole] || [] : OWNER_PERMISSIONS);

function readToken(req, res) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      code: 'NO_TOKEN',
      message: 'Access denied. No token provided.',
    });
    return null;
  }
  try {
    return jwt.verify(authHeader.split(' ')[1], process.env.JWT_SECRET);
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      res.status(401).json({
        success: false,
        code: 'TOKEN_EXPIRED',
        message: 'Your session has expired. Please sign in again.',
      });
    } else {
      res.status(401).json({
        success: false,
        code: 'INVALID_TOKEN',
        message: 'Invalid session. Please sign in again.',
      });
    }
    return null;
  }
}

function authenticateWith({ allowStaff }) {
  return async (req, res, next) => {
    const decoded = readToken(req, res);
    if (!decoded) return;

    // Attach decoded user info to request
    req.user = {
      userId: decoded.userId,
      role: decoded.role,
      vendorId: decoded.vendorId || null,
      staff: null,
    };
    if (!decoded.staffId) return next();

    if (!allowStaff) {
      return res.status(403).json({
        success: false,
        code: 'STAFF_NOT_ALLOWED',
        message: 'Only the store owner can do this. Switch back to the owner account.',
      });
    }
    try {
      // A deactivated staff member is signed out at once, whatever their token says
      const r = await pool.query(
        'SELECT id, full_name, role FROM vendor_staff WHERE id = $1 AND vendor_id = $2 AND is_active',
        [decoded.staffId, decoded.vendorId]
      );
      if (r.rows.length === 0) {
        return res.status(401).json({
          success: false,
          code: 'STAFF_INACTIVE',
          message: 'This staff account was removed. Ask the store owner to sign in.',
        });
      }
      req.user.staff = { id: r.rows[0].id, fullName: r.rows[0].full_name, role: r.rows[0].role };
      next();
    } catch (err) {
      next(err);
    }
  };
}

/**
 * Main authentication middleware
 * Extracts and verifies JWT from Authorization header
 * Attaches user object { userId, role, vendorId, staff } to req.user
 */
const authenticate = authenticateWith({ allowStaff: false });
const authenticateAllowStaff = authenticateWith({ allowStaff: true });

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

/** Store permission check: the owner passes, staff need the permission for their role */
const requirePermission = (permission) => (req, res, next) => {
  if (permissionsOf(req.user?.staff?.role).includes(permission)) return next();
  return res.status(403).json({
    success: false,
    code: 'STAFF_FORBIDDEN',
    message: `A ${req.user.staff.role.replace('_', ' ')} can't do this. Ask the store owner or switch user.`,
  });
};

// Convenience middleware for specific roles
const requireVendor = requireRole('vendor');
const requireCustomer = requireRole('customer');
const requireAdmin = requireRole('admin');
const requireOwner = requirePermission('owner');

module.exports = {
  authenticate,
  authenticateAllowStaff,
  requireRole,
  requirePermission,
  requireVendor,
  requireCustomer,
  requireAdmin,
  requireOwner,
  permissionsOf,
  STAFF_PERMISSIONS,
};
