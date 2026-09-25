// ══════════════════════════════════════════════════════════════
// File storage — dispute evidence (private) and product photos (public).
//
//   UPLOAD_DIR/evidence/  served only through signed, expiring links
//                         /api/files/evidence/<name>?exp=…&sig=…  (SSR 03)
//   UPLOAD_DIR/products/  served publicly at /uploads/products/<name>
//
// Default UPLOAD_DIR is backend/uploads. Hosting disks are wiped on redeploy:
// in production point UPLOAD_DIR at a persistent volume, or swap this module
// for object storage (e.g. Cloudflare R2).
// ══════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');

const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, '..', '..', 'uploads'));
const EVIDENCE_DIR = path.join(UPLOAD_DIR, 'evidence');
const PRODUCTS_DIR = path.join(UPLOAD_DIR, 'products');
const PRODUCTS_PUBLIC_PATH = '/uploads/products';

const MAX_EVIDENCE_FILES = 4;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const SIGNED_URL_TTL_SEC = 60 * 60;
const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);
const SAFE_NAME = /^[\w.-]+$/;

for (const dir of [EVIDENCE_DIR, PRODUCTS_DIR]) fs.mkdirSync(dir, { recursive: true });

function imageUploader(destination, limits) {
  return multer({
    storage: multer.diskStorage({
      destination,
      filename: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '') || '.jpg';
        cb(null, `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`);
      },
    }),
    limits: { fileSize: MAX_FILE_BYTES, ...limits },
    fileFilter: (req, file, cb) => {
      if (ALLOWED_TYPES.has(file.mimetype)) cb(null, true);
      else cb(Object.assign(new Error('Photos must be JPEG, PNG, WebP or HEIC images.'), { statusCode: 400 }));
    },
  });
}

const evidenceUpload = imageUploader(EVIDENCE_DIR, { files: MAX_EVIDENCE_FILES });
const productImageUpload = imageUploader(PRODUCTS_DIR, { files: 1 });

// ──────────────────────────────────────
// Evidence: stored as its file name, shown through signed links
// ──────────────────────────────────────

function sign(name, exp) {
  return crypto
    .createHmac('sha256', process.env.JWT_SECRET || 'dev-secret')
    .update(`evidence:${name}:${exp}`)
    .digest('base64url')
    .slice(0, 32);
}

/** Older rows stored "/uploads/<name>"; newer rows store just the name */
const evidenceName = (stored) => path.basename(String(stored));

/** Link valid for an hour, for people already allowed to see the dispute */
function signedEvidenceUrl(stored) {
  const name = evidenceName(stored);
  // Round expiry up to the next 10 minutes so repeated views reuse the same URL (browser cache)
  const exp = Math.ceil((Date.now() / 1000 + SIGNED_URL_TTL_SEC) / 600) * 600;
  return `/api/files/evidence/${encodeURIComponent(name)}?exp=${exp}&sig=${sign(name, exp)}`;
}

/** Absolute path of a validly signed evidence file, or null */
function resolveSignedEvidence(name, exp, sig) {
  if (!SAFE_NAME.test(name || '') || !/^\d+$/.test(exp || '') || typeof sig !== 'string') return null;
  if (Number(exp) < Date.now() / 1000) return null;
  const expected = sign(name, exp);
  if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  for (const dir of [EVIDENCE_DIR, UPLOAD_DIR]) {
    const file = path.join(dir, name);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

function removeEvidenceFiles(files = []) {
  for (const f of files) fs.unlink(path.join(EVIDENCE_DIR, f.filename), () => {});
}

// ──────────────────────────────────────
// Product photos: public
// ──────────────────────────────────────

const productImageUrl = (file) => `${PRODUCTS_PUBLIC_PATH}/${file.filename}`;

function removeProductImage(imageUrl) {
  if (!imageUrl || !imageUrl.startsWith(`${PRODUCTS_PUBLIC_PATH}/`)) return;
  const name = path.basename(imageUrl);
  if (SAFE_NAME.test(name)) fs.unlink(path.join(PRODUCTS_DIR, name), () => {});
}

module.exports = {
  UPLOAD_DIR,
  PRODUCTS_DIR,
  PRODUCTS_PUBLIC_PATH,
  MAX_EVIDENCE_FILES,
  evidenceUpload,
  productImageUpload,
  evidenceName,
  signedEvidenceUrl,
  resolveSignedEvidence,
  removeEvidenceFiles,
  productImageUrl,
  removeProductImage,
};
