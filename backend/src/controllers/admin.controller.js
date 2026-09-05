// ══════════════════════════════════════════════════════════════
// Vendra Backend - Admin Controller
// Handles platform stats, vendor approval, user & order monitoring
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { getEscrowPoolBalanceReadOnly } = require('../services/escrowPool.service');

/**
 * GET /api/admin/stats
 * Dashboard KPI stats: vendors, customers, orders, revenue, pending approvals
 */
const getDashboardStats = async (req, res) => {
  try {
    const stats = {};

    // Total approved vendors
    const vendorsResult = await pool.query(
      `SELECT 
        COUNT(*) FILTER (WHERE is_approved = true) AS approved,
        COUNT(*) FILTER (WHERE is_approved = false) AS pending,
        COUNT(*) AS total
       FROM vendors`
    );
    stats.vendors = vendorsResult.rows[0];

    // Total customers
    const customersResult = await pool.query(
      `SELECT COUNT(*) AS total FROM users WHERE role = 'customer'`
    );
    stats.customers = parseInt(customersResult.rows[0].total);

    // Total riders
    const ridersResult = await pool.query(
      `SELECT COUNT(*) AS total FROM users WHERE role = 'rider'`
    );
    stats.riders = parseInt(ridersResult.rows[0].total);

    // Orders stats
    const ordersResult = await pool.query(
      `SELECT 
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE) AS today,
        COALESCE(SUM(total_amount), 0) AS total_revenue,
        COALESCE(SUM(total_amount) FILTER (WHERE created_at::date = CURRENT_DATE), 0) AS today_revenue
       FROM orders`
    );
    stats.orders = {
      total: parseInt(ordersResult.rows[0].total),
      today: parseInt(ordersResult.rows[0].today),
      totalRevenue: parseFloat(ordersResult.rows[0].total_revenue),
      todayRevenue: parseFloat(ordersResult.rows[0].today_revenue),
    };

    // Products count
    const productsResult = await pool.query(
      `SELECT COUNT(*) AS total FROM products WHERE is_active = true`
    );
    stats.products = parseInt(productsResult.rows[0].total);

    // Escrow held amount
    stats.escrowHeld = await getEscrowPoolBalanceReadOnly();

    res.json({ success: true, data: stats });
  } catch (error) {
    console.error('Dashboard stats error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch stats.' });
  }
};

/**
 * GET /api/admin/vendors
 * List all vendors with user info, CNIC, approval status, product count
 */
const getAllVendors = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT v.id, v.store_name, v.store_address, v.cnic, v.is_approved, v.created_at,
              u.id AS user_id, u.full_name, u.email, u.phone,
              COUNT(p.id) AS product_count,
              COALESCE(SUM(CASE WHEN o.status != 'cancelled' THEN o.total_amount ELSE 0 END), 0) AS total_revenue
       FROM vendors v
       JOIN users u ON u.id = v.user_id
       LEFT JOIN products p ON p.vendor_id = v.id AND p.is_active = true
       LEFT JOIN orders o ON o.vendor_id = v.id
       GROUP BY v.id, u.id
       ORDER BY v.created_at DESC`
    );

    res.json({
      success: true,
      data: result.rows.map((v) => ({
        id: v.id,
        userId: v.user_id,
        storeName: v.store_name,
        storeAddress: v.store_address,
        cnic: v.cnic,
        isApproved: v.is_approved,
        ownerName: v.full_name,
        email: v.email,
        phone: v.phone,
        productCount: parseInt(v.product_count),
        totalRevenue: parseFloat(v.total_revenue),
        createdAt: v.created_at,
      })),
    });
  } catch (error) {
    console.error('Get vendors error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch vendors.' });
  }
};

/**
 * PUT /api/admin/vendors/:id/approve
 * Approve a vendor (set is_approved = true)
 */
const approveVendor = async (req, res) => {
  try {
    const vendorId = req.params.id;

    const result = await pool.query(
      `UPDATE vendors SET is_approved = true WHERE id = $1
       RETURNING id, store_name, is_approved`,
      [vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Vendor not found.' });
    }

    res.json({
      success: true,
      message: `Vendor "${result.rows[0].store_name}" has been approved.`,
      data: result.rows[0],
    });
  } catch (error) {
    console.error('Approve vendor error:', error);
    res.status(500).json({ success: false, message: 'Failed to approve vendor.' });
  }
};

/**
 * PUT /api/admin/vendors/:id/disapprove
 * Disapprove/suspend a vendor (set is_approved = false)
 */
const disapproveVendor = async (req, res) => {
  try {
    const vendorId = req.params.id;

    const result = await pool.query(
      `UPDATE vendors SET is_approved = false WHERE id = $1
       RETURNING id, store_name, is_approved`,
      [vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Vendor not found.' });
    }

    res.json({
      success: true,
      message: `Vendor "${result.rows[0].store_name}" has been disapproved.`,
      data: result.rows[0],
    });
  } catch (error) {
    console.error('Disapprove vendor error:', error);
    res.status(500).json({ success: false, message: 'Failed to disapprove vendor.' });
  }
};

/**
 * GET /api/admin/orders
 * List all orders across the platform
 */
const getAllOrders = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT o.id, o.status, o.total_amount, o.created_at, o.updated_at,
              u.full_name AS customer_name, u.email AS customer_email,
              v.store_name,
              COUNT(oi.id) AS item_count
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       JOIN vendors v ON v.id = o.vendor_id
       JOIN order_items oi ON oi.order_id = o.id
       GROUP BY o.id, u.full_name, u.email, v.store_name
       ORDER BY o.created_at DESC`
    );

    res.json({
      success: true,
      data: result.rows.map((o) => ({
        id: o.id,
        customerName: o.customer_name,
        customerEmail: o.customer_email,
        storeName: o.store_name,
        status: o.status,
        totalAmount: parseFloat(o.total_amount),
        itemCount: parseInt(o.item_count),
        createdAt: o.created_at,
        updatedAt: o.updated_at,
      })),
    });
  } catch (error) {
    console.error('Get all orders error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch orders.' });
  }
};

/**
 * GET /api/admin/users
 * List all users with role breakdown
 */
const getAllUsers = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.phone, u.role, u.created_at,
              v.store_name, v.is_approved
       FROM users u
       LEFT JOIN vendors v ON u.vendor_id = v.id
       ORDER BY u.created_at DESC`
    );

    res.json({
      success: true,
      data: result.rows.map((u) => ({
        id: u.id,
        fullName: u.full_name,
        email: u.email,
        phone: u.phone,
        role: u.role,
        storeName: u.store_name || null,
        isApproved: u.is_approved,
        createdAt: u.created_at,
      })),
    });
  } catch (error) {
    console.error('Get all users error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch users.' });
  }
};

module.exports = {
  getDashboardStats,
  getAllVendors,
  approveVendor,
  disapproveVendor,
  getAllOrders,
  getAllUsers,
};
