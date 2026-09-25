// ══════════════════════════════════════════════════════════════
// Vendra Backend - Auth Controller
// Handles user registration, login, and profile retrieval
// ══════════════════════════════════════════════════════════════

const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('../db');
const { getEscrowPoolBalanceReadOnly } = require('../services/escrowPool.service');

const SALT_ROUNDS = 10;
const JWT_EXPIRY = '7d'; // Token valid for 7 days

/**
 * POST /api/auth/signup
 * Register a new user. If role is 'vendor', auto-creates vendor record.
 * Body: { fullName, email, password, role, storeName?, cnic?, phone? }
 */
const signup = async (req, res) => {
  const client = await pool.connect();

  try {
    const { fullName, email, password, role, storeName, cnic, phone, vehicleType } = req.body;

    // Validate required fields
    if (!fullName || !email || !password || !role) {
      return res.status(400).json({
        success: false,
        message: 'Full name, email, password, and role are required.',
      });
    }

    // Validate role
    const validRoles = ['customer', 'vendor', 'rider'];
    if (!validRoles.includes(role)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid role. Must be customer, vendor, or rider.',
      });
    }

    // Vendor must provide CNIC
    if (role === 'vendor' && !cnic) {
      return res.status(400).json({
        success: false,
        message: 'CNIC is required for vendor registration.',
      });
    }

    // Check if email already exists
    const existingUser = await client.query(
      'SELECT id FROM users WHERE email = $1',
      [email.toLowerCase()]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({
        success: false,
        message: 'Email already registered.',
      });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    // Begin transaction (needed for vendor creation with circular FK)
    await client.query('BEGIN');
    await client.query('SET CONSTRAINTS ALL DEFERRED');

    // Insert user
    const userResult = await client.query(
      `INSERT INTO users (full_name, email, phone, password_hash, role)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, full_name, email, phone, role, created_at`,
      [fullName, email.toLowerCase(), phone || null, passwordHash, role]
    );

    const user = userResult.rows[0];
    let vendorId = null;
    let isApproved = null;

    // If vendor, create vendor record and link
    if (role === 'vendor') {
      const vendorStoreName = storeName || `${fullName}'s Store`;

      const vendorResult = await client.query(
        `INSERT INTO vendors (user_id, store_name, cnic, is_approved)
         VALUES ($1, $2, $3, false)
         RETURNING id, store_name, is_approved`,
        [user.id, vendorStoreName, cnic]
      );

      vendorId = vendorResult.rows[0].id;
      isApproved = vendorResult.rows[0].is_approved;

      // Update user with vendor_id
      await client.query(
        'UPDATE users SET vendor_id = $1 WHERE id = $2',
        [vendorId, user.id]
      );
    }

    // If rider, create rider record
    if (role === 'rider') {
      await client.query(
        'INSERT INTO riders (user_id, vehicle_type) VALUES ($1, $2)',
        [user.id, vehicleType || 'motorbike']
      );
    }

    await client.query('COMMIT');

    // Generate JWT token
    const token = jwt.sign(
      {
        userId: user.id,
        role: user.role,
        vendorId: vendorId,
      },
      process.env.JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.status(201).json({
      success: true,
      message: role === 'vendor'
        ? 'Vendor account created! Awaiting admin approval.'
        : 'Account created successfully.',
      data: {
        token,
        user: {
          id: user.id,
          fullName: user.full_name,
          email: user.email,
          phone: user.phone,
          role: user.role,
          vendorId: vendorId,
          isApproved: isApproved,
          createdAt: user.created_at,
        },
      },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Signup error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create account.',
    });
  } finally {
    client.release();
  }
};

const APP_NAMES = {
  customer: 'Vendra',
  vendor: 'Vendra Vendor',
  rider: 'Vendra Rider',
  admin: 'Vendra Admin dashboard',
};

/**
 * POST /api/auth/login
 * Authenticate user and return JWT token.
 * Body: { email, password, role? } — each app sends its role so a vendor
 * can't sign in to the rider app (and so on).
 */
const login = async (req, res) => {
  try {
    const { email, password, role: expectedRole } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required.',
      });
    }

    // Find user by email
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.phone, u.password_hash, u.role, u.vendor_id, u.wallet_balance,
              u.must_change_password, v.store_name, v.is_approved, v.cnic
       FROM users u
       LEFT JOIN vendors v ON u.vendor_id = v.id
       WHERE u.email = $1`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password.',
      });
    }

    const user = result.rows[0];

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.password_hash);
    if (!isValidPassword) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password.',
      });
    }

    if (expectedRole && expectedRole !== user.role) {
      return res.status(403).json({
        success: false,
        code: 'WRONG_APP',
        message: `This is a ${user.role} account. Please sign in with the ${APP_NAMES[user.role] || user.role} app.`,
      });
    }

    // Generate JWT token
    const token = jwt.sign(
      {
        userId: user.id,
        role: user.role,
        vendorId: user.vendor_id,
      },
      process.env.JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    const platformEscrowBalance = await getEscrowPoolBalanceReadOnly();

    res.json({
      success: true,
      message: 'Login successful.',
      data: {
        token,
        user: {
          id: user.id,
          fullName: user.full_name,
          email: user.email,
          phone: user.phone,
          role: user.role,
          walletBalance: parseFloat(user.wallet_balance),
          vendorId: user.vendor_id,
          storeName: user.store_name || null,
          isApproved: user.is_approved,
          cnic: user.cnic || null,
          mustChangePassword: user.must_change_password,
          platformEscrowBalance,
        },
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      success: false,
      message: 'Login failed.',
    });
  }
};

/**
 * GET /api/auth/me
 * Get current authenticated user's profile.
 */
const getMe = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.phone, u.role, u.vendor_id, u.wallet_balance, u.created_at, u.must_change_password,
              v.store_name, v.store_address, v.is_approved, v.cnic, v.latitude AS store_lat, v.longitude AS store_lng,
              r.vehicle_type, r.is_online
       FROM users u
       LEFT JOIN vendors v ON u.vendor_id = v.id
       LEFT JOIN riders r ON r.user_id = u.id
       WHERE u.id = $1`,
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User not found.',
      });
    }

    const user = result.rows[0];

    const platformEscrowBalance = await getEscrowPoolBalanceReadOnly();

    res.json({
      success: true,
      data: {
        id: user.id,
        fullName: user.full_name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        walletBalance: parseFloat(user.wallet_balance),
        vendorId: user.vendor_id,
        storeName: user.store_name || null,
        storeAddress: user.store_address || null,
        isApproved: user.is_approved,
        cnic: user.cnic || null,
        storeLat: user.store_lat != null ? Number(user.store_lat) : null,
        storeLng: user.store_lng != null ? Number(user.store_lng) : null,
        vehicleType: user.vehicle_type || null,
        isOnline: user.is_online ?? null,
        mustChangePassword: user.must_change_password,
        createdAt: user.created_at,
        platformEscrowBalance,
      },
    });
  } catch (error) {
    console.error('GetMe error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch profile.',
    });
  }
};

const MIN_PASSWORD_LENGTH = 8;

/**
 * POST /api/auth/change-password
 * Body: { currentPassword, newPassword } — also clears a temporary password set by an admin.
 */
const changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ success: false, message: 'Current and new password are required.' });
    }
    if (String(newPassword).length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ success: false, message: `New password must be at least ${MIN_PASSWORD_LENGTH} characters.` });
    }
    if (newPassword === currentPassword) {
      return res.status(400).json({ success: false, message: 'Choose a password different from the current one.' });
    }

    const r = await pool.query('SELECT password_hash FROM users WHERE id = $1', [req.user.userId]);
    if (r.rows.length === 0) return res.status(404).json({ success: false, message: 'User not found.' });
    if (!(await bcrypt.compare(currentPassword, r.rows[0].password_hash))) {
      return res.status(401).json({ success: false, code: 'WRONG_PASSWORD', message: 'Current password is incorrect.' });
    }

    const hash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await pool.query(
      `UPDATE users SET password_hash = $1, must_change_password = false, password_changed_at = NOW() WHERE id = $2`,
      [hash, req.user.userId]
    );
    res.json({ success: true, message: 'Password changed.' });
  } catch (error) {
    console.error('Change password error:', error);
    res.status(500).json({ success: false, message: 'Failed to change password.' });
  }
};

module.exports = { signup, login, getMe, changePassword, SALT_ROUNDS, MIN_PASSWORD_LENGTH };
