// ══════════════════════════════════════════════════════════════
// Creates an admin account — how the first admin gets in when demo data
// isn't loaded (production mode). Works in both modes.
//   npm run admin:create -- <email> "<full name>"
// The password is read from ADMIN_PASSWORD, or generated and printed once.
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const crypto = require('crypto');
const bcrypt = require('bcrypt');
const { Client } = require('pg');
const { SALT_ROUNDS, MIN_PASSWORD_LENGTH } = require('./controllers/auth.controller');

async function main() {
  const [email, ...nameParts] = process.argv.slice(2);
  const fullName = nameParts.join(' ').trim() || 'Vendra Admin';
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new Error('Usage: npm run admin:create -- <email> "<full name>"');
  }
  const generated = !process.env.ADMIN_PASSWORD;
  const password = process.env.ADMIN_PASSWORD || crypto.randomBytes(12).toString('base64url');
  if (password.length < MIN_PASSWORD_LENGTH) throw new Error(`ADMIN_PASSWORD must be at least ${MIN_PASSWORD_LENGTH} characters.`);

  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const hash = await bcrypt.hash(password, SALT_ROUNDS);
    const r = await client.query(
      `INSERT INTO users (full_name, email, password_hash, role, must_change_password)
       VALUES ($1, $2, $3, 'admin', $4)
       ON CONFLICT (email) DO NOTHING RETURNING id`,
      [fullName, email.toLowerCase(), hash, generated]
    );
    if (r.rows.length === 0) throw new Error(`${email} already has an account.`);
    console.log(`✓ Admin ${email} created.`);
    if (generated) console.log(`  Temporary password: ${password}  (they must change it after signing in)`);
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('✗', err.message);
  process.exit(1);
});
