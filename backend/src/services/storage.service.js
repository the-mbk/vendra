// ══════════════════════════════════════════════════════════════
// File storage — dispute evidence (private) and product photos (public).
//
// Two drivers behind one interface:
//   s3     any S3-compatible bucket: SeaweedFS locally (docker-compose), Cloudflare R2
//          in production. Used when S3_BUCKET is set (or STORAGE_DRIVER=s3).
//   local  files under UPLOAD_DIR (default backend/uploads). Used by the tests and
//          when no bucket is configured.
//
// Objects are stored as <kind>/<name> (kind = evidence | products). The bucket stays
// private either way; the backend streams files out, so URLs never change:
//   product photos  /uploads/products/<name>                      public, cached 7 days
//   evidence        /api/files/evidence/<name>?exp=…&sig=…        signed, expires (SSR 03)
// ══════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');

const MAX_EVIDENCE_FILES = 4;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const SIGNED_URL_TTL_SEC = 60 * 60;
const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);
const SAFE_NAME = /^[\w.-]+$/;
const PRODUCTS_PUBLIC_PATH = '/uploads/products';
const KINDS = new Set(['evidence', 'products']);

const CONTENT_TYPES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.heic': 'image/heic' };
const contentTypeOf = (name) => CONTENT_TYPES[path.extname(name).toLowerCase()] || 'application/octet-stream';

// ──────────────────────────────────────
// Drivers: save(kind, name, buffer, type) · open(kind, name) → { stream, type, size } | null · remove(kind, name)
// ──────────────────────────────────────

function localDriver() {
  const root = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, '..', '..', 'uploads'));
  for (const kind of KINDS) fs.mkdirSync(path.join(root, kind), { recursive: true });
  // Evidence uploaded before the evidence/ folder existed sits directly in UPLOAD_DIR
  const candidates = (kind, name) => (kind === 'evidence' ? [path.join(root, kind, name), path.join(root, name)] : [path.join(root, kind, name)]);

  return {
    name: 'local',
    root,
    async save(kind, name, buffer) {
      await fs.promises.writeFile(path.join(root, kind, name), buffer);
    },
    async open(kind, name) {
      for (const file of candidates(kind, name)) {
        try {
          const stat = await fs.promises.stat(file);
          if (stat.isFile()) return { stream: fs.createReadStream(file), type: contentTypeOf(name), size: stat.size };
        } catch { /* try the next location */ }
      }
      return null;
    },
    async remove(kind, name) {
      await fs.promises.unlink(path.join(root, kind, name)).catch(() => {});
    },
  };
}

function s3Driver() {
  const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadBucketCommand, CreateBucketCommand } = require('@aws-sdk/client-s3');
  const bucket = process.env.S3_BUCKET;
  if (!bucket) throw new Error('STORAGE_DRIVER=s3 needs S3_BUCKET (and S3_ENDPOINT, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY).');

  const client = new S3Client({
    endpoint: process.env.S3_ENDPOINT || undefined,
    region: process.env.S3_REGION || 'auto', // R2 uses "auto"; SeaweedFS accepts anything
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== 'false',
    credentials: process.env.S3_ACCESS_KEY_ID
      ? { accessKeyId: process.env.S3_ACCESS_KEY_ID, secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || '' }
      : undefined,
  });
  const key = (kind, name) => `${kind}/${name}`;

  return {
    name: 's3',
    bucket,
    /** Creates the bucket if it's missing (local SeaweedFS). R2 buckets are created in the dashboard. */
    async ensureBucket() {
      try {
        await client.send(new HeadBucketCommand({ Bucket: bucket }));
      } catch (err) {
        if (err.$metadata?.httpStatusCode !== 404 && err.name !== 'NotFound') throw err;
        await client.send(new CreateBucketCommand({ Bucket: bucket }));
      }
    },
    async save(kind, name, buffer, type) {
      await client.send(new PutObjectCommand({ Bucket: bucket, Key: key(kind, name), Body: buffer, ContentType: type }));
    },
    async open(kind, name) {
      try {
        const r = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key(kind, name) }));
        return { stream: r.Body, type: r.ContentType || contentTypeOf(name), size: r.ContentLength };
      } catch (err) {
        if (err.name === 'NoSuchKey' || err.$metadata?.httpStatusCode === 404) return null;
        throw err;
      }
    },
    async remove(kind, name) {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key(kind, name) })).catch(() => {});
    },
  };
}

const driverName = process.env.STORAGE_DRIVER || (process.env.S3_BUCKET ? 's3' : 'local');
const driver = driverName === 's3' ? s3Driver() : localDriver();

/** Called once at start-up: makes sure the bucket exists and is reachable */
async function initStorage() {
  if (driver.ensureBucket) await driver.ensureBucket();
  return driver.name === 's3' ? `S3 bucket "${driver.bucket}" at ${process.env.S3_ENDPOINT || 'AWS'}` : `local folder ${driver.root}`;
}

// ──────────────────────────────────────
// Uploads: a multer storage engine that writes through the driver.
// Controllers read file.filename, as with multer's disk storage.
// ──────────────────────────────────────

function driverEngine(kind) {
  return {
    _handleFile(req, file, cb) {
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '') || '.jpg';
      const name = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
      const chunks = [];
      let size = 0;
      file.stream.on('data', (c) => { chunks.push(c); size += c.length; });
      file.stream.on('error', cb);
      file.stream.on('end', () => {
        driver
          .save(kind, name, Buffer.concat(chunks), file.mimetype)
          .then(() => cb(null, { filename: name, size }))
          .catch(cb);
      });
    },
    _removeFile(req, file, cb) {
      driver.remove(kind, file.filename).then(() => cb(null), () => cb(null));
    },
  };
}

function imageUploader(kind, limits) {
  return multer({
    storage: driverEngine(kind),
    limits: { fileSize: MAX_FILE_BYTES, ...limits },
    fileFilter: (req, file, cb) => {
      if (ALLOWED_TYPES.has(file.mimetype)) cb(null, true);
      else cb(Object.assign(new Error('Photos must be JPEG, PNG, WebP or HEIC images.'), { statusCode: 400 }));
    },
  });
}

const evidenceUpload = imageUploader('evidence', { files: MAX_EVIDENCE_FILES });
const productImageUpload = imageUploader('products', { files: 1 });

/** Streams a stored file to the response; false when it doesn't exist */
async function sendStoredFile(res, kind, name, cacheControl) {
  if (!KINDS.has(kind) || !SAFE_NAME.test(name || '')) return false;
  const file = await driver.open(kind, name);
  if (!file) return false;
  res.set('Content-Type', file.type);
  if (file.size != null) res.set('Content-Length', String(file.size));
  res.set('Cache-Control', cacheControl);
  file.stream.on('error', () => res.destroy());
  file.stream.pipe(res);
  return true;
}

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

/** True when the link's signature is valid and it hasn't expired */
function verifyEvidenceLink(name, exp, sig) {
  if (!SAFE_NAME.test(name || '') || !/^\d+$/.test(exp || '') || typeof sig !== 'string') return false;
  if (Number(exp) < Date.now() / 1000) return false;
  const expected = sign(name, exp);
  return sig.length === expected.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
}

function removeEvidenceFiles(files = []) {
  for (const f of files) driver.remove('evidence', f.filename);
}

// ──────────────────────────────────────
// Product photos: public
// ──────────────────────────────────────

const productImageUrl = (file) => `${PRODUCTS_PUBLIC_PATH}/${file.filename}`;

/** Catalogue photos from the demo data are shared by many products and never deleted */
const SHARED_PHOTO = /^catalog-/;

function removeProductImage(imageUrl) {
  if (!imageUrl || !imageUrl.startsWith(`${PRODUCTS_PUBLIC_PATH}/`)) return;
  const name = path.basename(imageUrl);
  if (SAFE_NAME.test(name) && !SHARED_PHOTO.test(name)) driver.remove('products', name);
}

module.exports = {
  PRODUCTS_PUBLIC_PATH,
  MAX_EVIDENCE_FILES,
  storageDriver: driver,
  initStorage,
  evidenceUpload,
  productImageUpload,
  sendStoredFile,
  evidenceName,
  signedEvidenceUrl,
  verifyEvidenceLink,
  removeEvidenceFiles,
  productImageUrl,
  removeProductImage,
};
