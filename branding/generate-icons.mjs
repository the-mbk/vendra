// ══════════════════════════════════════════════════════════════
// Vendra brand icons: writes the SVG masters and every PNG / ICO the
// three Flutter apps (Android launcher + adaptive + web) and the admin
// panel need, then installs them.
//
//   node branding/generate-icons.mjs
//
// Rasterised with sharp (librsvg), borrowed from the admin panel's
// node_modules, so nothing extra has to be installed.
// ══════════════════════════════════════════════════════════════

import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const require = createRequire(join(root, 'frontend-admin', 'package.json'));
const sharp = require('sharp');

const NAVY = '#232774';
const ORANGE = '#FD761A';
const WHITE = '#FFFFFF';

// ── The mark, on a 100 × 100 grid ─────────────────────────────
// A geometric V whose right arm stops short; the dot above it is the
// "nearby" pin that every Vendra app is built around.
const V = '16,20 35,20 50,56 59.17,34 78.17,34 59,80 41,80';
const DOT = { cx: 75.2, cy: 18.3, r: 8.6 };
// Two trails behind the dot: the rider variant is the mark in motion
const TRAILS = [
  { x1: 44, x2: 61, y: 13.6 },
  { x1: 50, x2: 61, y: 23.0 },
];
// The mark spans y 9.7–80 and x 16–84: this centres it on (50, 50)
const CENTRE = 'translate(0 5.15)';

const VARIANTS = {
  customer: { name: 'Vendra', bg: ORANGE, v: WHITE, dot: NAVY, motion: false },
  vendor: { name: 'Vendra Vendor', bg: NAVY, v: WHITE, dot: ORANGE, motion: false },
  rider: { name: 'Vendra Rider', bg: WHITE, v: NAVY, dot: ORANGE, motion: true },
  admin: { name: 'Vendra Admin', bg: NAVY, v: WHITE, dot: ORANGE, motion: false },
};

/** The mark alone; [mono] paints everything white (Android themed icons) */
function mark(variant, { mono = false } = {}) {
  const c = (colour) => (mono ? WHITE : colour);
  const trails = variant.motion
    ? TRAILS.map((t) => `<line x1="${t.x1}" y1="${t.y}" x2="${t.x2}" y2="${t.y}" stroke="${c(variant.dot)}" stroke-width="4.2" stroke-linecap="round"/>`).join('')
    : '';
  return `<g transform="${CENTRE}">`
    + `<polygon points="${V}" fill="${c(variant.v)}" stroke="${c(variant.v)}" stroke-width="3" stroke-linejoin="round"/>`
    + `<circle cx="${DOT.cx}" cy="${DOT.cy}" r="${DOT.r}" fill="${c(variant.dot)}"/>`
    + trails
    + '</g>';
}

/** [scale] of the mark around the centre of a [size] canvas */
function placed(variant, size, scale, opts) {
  const k = (size / 100) * scale;
  const offset = (size - 100 * k) / 2;
  return `<g transform="translate(${offset} ${offset}) scale(${k})">${mark(variant, opts)}</g>`;
}

const svg = (size, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">${body}</svg>`;

/** Rounded tile: legacy launcher, web icons, favicon, master artwork */
const tile = (variant, size = 512) => {
  // A white tile needs an edge on white launchers and browser tabs
  const edge = variant.bg === WHITE
    ? `<rect x="${size * 0.006}" y="${size * 0.006}" width="${size * 0.988}" height="${size * 0.988}" rx="${size * 0.22}" fill="none" stroke="#DADCEB" stroke-width="${size * 0.012}"/>`
    : '';
  return svg(size, `<rect width="${size}" height="${size}" rx="${size * 0.225}" fill="${variant.bg}"/>${edge}${placed(variant, size, 0.8)}`);
};
/** Full-bleed square, mark inside the maskable safe circle (40 % radius) */
const maskable = (variant, size) => svg(size, `<rect width="${size}" height="${size}" fill="${variant.bg}"/>${placed(variant, size, 0.62)}`);
/** Adaptive icon layers: 108 dp canvas, the mark within the 66 dp safe zone */
const foreground = (variant, size, opts) => svg(size, placed(variant, size, 0.62, opts));

async function png(svgText, size, file) {
  mkdirSync(dirname(file), { recursive: true });
  await sharp(Buffer.from(svgText), { density: 72 }).resize(size, size).png({ compressionLevel: 9 }).toFile(file);
}

/** .ico holding PNG images (Vista+ and every browser read these) */
async function ico(svgText, sizes, file) {
  const images = await Promise.all(sizes.map((s) => sharp(Buffer.from(svgText)).resize(s, s).png().toBuffer()));
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  images.forEach((img, i) => {
    const at = 6 + 16 * i;
    header.writeUInt8(sizes[i] >= 256 ? 0 : sizes[i], at);
    header.writeUInt8(sizes[i] >= 256 ? 0 : sizes[i], at + 1);
    header.writeUInt16LE(1, at + 4); // colour planes
    header.writeUInt16LE(32, at + 6); // bits per pixel
    header.writeUInt32LE(img.length, at + 8);
    header.writeUInt32LE(offset, at + 12);
    offset += img.length;
  });
  writeFileSync(file, Buffer.concat([header, ...images]));
}

const write = (file, text) => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, text);
};

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function flutterApp(app) {
  const variant = VARIANTS[app];
  const base = join(root, `frontend-${app}`);
  const res = join(base, 'android', 'app', 'src', 'main', 'res');

  // Android: legacy icon (48 dp) + adaptive layers (108 dp) + themed monochrome
  for (const [density, k] of Object.entries(DENSITIES)) {
    await png(tile(variant, 192), 48 * k, join(res, `mipmap-${density}`, 'ic_launcher.png'));
    await png(foreground(variant, 432), 108 * k, join(res, `mipmap-${density}`, 'ic_launcher_foreground.png'));
    await png(foreground(variant, 432, { mono: true }), 108 * k, join(res, `mipmap-${density}`, 'ic_launcher_monochrome.png'));
  }
  write(join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
    `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by branding/generate-icons.mjs -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
`);
  write(join(res, 'values', 'ic_launcher_background.xml'),
    `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by branding/generate-icons.mjs -->
<resources>
    <color name="ic_launcher_background">${variant.bg}</color>
</resources>
`);
  // Splash while the Flutter engine starts: brand colour + the mark
  const launch = `<?xml version="1.0" encoding="utf-8"?>
<!-- Splash shown while the Flutter engine starts (branding/generate-icons.mjs) -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/ic_launcher_background" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/ic_launcher_foreground" />
    </item>
</layer-list>
`;
  write(join(res, 'drawable', 'launch_background.xml'), launch);
  write(join(res, 'drawable-v21', 'launch_background.xml'), launch);

  // Web
  const web = join(base, 'web');
  await png(tile(variant, 192), 64, join(web, 'favicon.png'));
  await png(tile(variant, 512), 192, join(web, 'icons', 'Icon-192.png'));
  await png(tile(variant, 512), 512, join(web, 'icons', 'Icon-512.png'));
  await png(maskable(variant, 512), 192, join(web, 'icons', 'Icon-maskable-192.png'));
  await png(maskable(variant, 512), 512, join(web, 'icons', 'Icon-maskable-512.png'));
  const manifestFile = join(web, 'manifest.json');
  const manifest = JSON.parse(readFileSync(manifestFile, 'utf8'));
  manifest.name = variant.name;
  manifest.short_name = variant.name;
  manifest.background_color = variant.bg;
  manifest.theme_color = variant.bg === WHITE ? NAVY : variant.bg;
  write(manifestFile, `${JSON.stringify(manifest, null, 4)}\n`);
}

async function main() {
  // Masters
  for (const [app, variant] of Object.entries(VARIANTS)) {
    write(join(here, 'svg', `vendra-${app}.svg`), tile(variant));
    write(join(here, 'svg', `vendra-${app}-maskable.svg`), maskable(variant, 512));
    await png(tile(variant, 1024), 1024, join(here, 'png', `vendra-${app}-1024.png`));
    await png(tile(variant, 512), 512, join(here, 'png', `vendra-${app}-512.png`));
  }
  // The bare mark on transparent, for slides and documents
  const bare = { v: NAVY, dot: ORANGE, motion: false };
  write(join(here, 'svg', 'vendra-mark.svg'), svg(100, mark(bare)));
  await png(svg(512, placed(bare, 512, 1)), 512, join(here, 'png', 'vendra-mark-512.png'));

  for (const app of ['customer', 'vendor', 'rider']) await flutterApp(app);

  // Admin panel (Next.js app router picks up app/favicon.ico and app/icon.svg)
  const admin = join(root, 'frontend-admin', 'app');
  await ico(tile(VARIANTS.admin, 256), [16, 32, 48], join(admin, 'favicon.ico'));
  write(join(admin, 'icon.svg'), tile(VARIANTS.admin));

  console.log('Vendra icons written.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
