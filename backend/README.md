# Vendra Backend

Node.js + Express + PostgreSQL API for Vendra, a multi-vendor marketplace with dual inventory (private vs public stock), atomic order reservation, escrow funded by card payments, rider delivery with GPS payouts, disputes and a policy engine. Realtime updates go over Socket.IO on the same port.

- Card payments go through **Vendra Pay** ([gateway/](gateway/README.md)), a local payment gateway sandbox with test cards, payouts and signed webhooks.

- API reference: [docs/API.md](docs/API.md)
- Requirements (SRDS): [docs/srds-clean.md](docs/srds-clean.md)

## Requirements

- Node.js 18+ (tests use the built-in `node:test` runner and `fetch`)
- PostgreSQL 16+

## Setup

```bash
npm install
cp .env.example .env        # DATABASE_URL already matches docker-compose.yml; set JWT_SECRET
npm run db:up               # Docker: Postgres (5433), SeaweedFS storage (8333), Vendra Pay gateway (4242)
npm run migrate             # applies migrations/NNN_*.sql once each
npm run seed                # demo marketplace (Islamabad & Rawalpindi) — empty database only
npm run dev                 # or: npm start
```

The API runs on `http://localhost:3000` (`GET /api/health`). `npm run db:down` stops the database and storage and keeps their data; `docker compose down -v` wipes both.

### Development and production mode

`APP_MODE` (default `development`) switches the demo helpers on or off. The apps read it from `GET /api/public-config`, so changing it only needs a backend restart.

| Feature | development | production |
|---|---|---|
| Riders can set their position by hand / simulate a drive | on | off (403 `MANUAL_LOCATION_DISABLED`) |
| Payment screens list the test cards and the OTP | on | off |
| Fast timers: dispute window ≤ 2 min, store response ≤ 5 min, rider search ≤ 10 min | on | off (the stored policies apply) |
| Login screens list the demo accounts; `npm run seed` allowed | on | off |
| Localhost origins allowed by CORS | on | off (`ALLOWED_ORIGINS` only) |
| Opening balances of the demo data are funded at the gateway | on | off |

Production mode refuses to start without a random `JWT_SECRET` (32+ characters) and `ALLOWED_ORIGINS`. Without demo data, create the first admin with `npm run admin:create -- admin@example.com "Full Name"` (prints a temporary password; set `ADMIN_PASSWORD` to choose one).

### Money

Money enters only through card payments at the gateway and leaves only through card payouts:

```
card ─gateway→ wallet ─checkout→ escrow ─release→ vendor / rider wallets ─withdrawal→ card
```

Admin → Finance → reconciliation checks that the gateway balance equals wallets + escrow + platform revenue (± money in flight). Seed money that never went through a card is an *opening balance*; in development the backend adds the same amount to its gateway balance once, so it can be withdrawn.

A sweep every 30 s releases escrow after the dispute window, cancels and refunds stalled orders, and catches up on any webhook that went missing.

### File storage

Photos go to an S3-compatible bucket, so local and production use the same code path:

- **Locally:** SeaweedFS (`vendra-storage` container) plays the part of Cloudflare R2. Browse the bucket at http://localhost:8888/buckets/. The bucket is private, like R2: the backend streams product photos at `/uploads/products/<name>` and evidence only through signed links.
- **Production:** point the `S3_*` variables at an R2 bucket. Nothing else changes.
- Photos saved on disk before the bucket existed: `npm run storage:import` copies them in (safe to rerun).

When all the repos sit side by side in one folder, `run-local.ps1` in that folder starts the database, applies migrations, loads demo data into an empty database, and opens the backend, admin dashboard and the three Flutter apps (in Chrome) in their own windows.

### Demo data

`npm run seed` fills an empty database with a marketplace in **Islamabad and Rawalpindi** (development mode only):

- **1,000 users:** 120 stores (about 9 waiting for approval), 150 riders, 729 customers and the admin. Run `npm run seed -- --users=3000` for a bigger city.
- **About 2,000 products:** groceries, electronics, fashion, beauty, home and sports stores, with real product photos and some products waiting for approval.
- **90 days of orders:** delivered, cancelled, and recent ones still in escrow. Wallets, rider earnings and platform revenue add up exactly.

Product names, descriptions and photos come from [DummyJSON](https://dummyjson.com), a free fake-data API. The first run downloads them into `.cache/`; later runs work offline. The photos go into the file storage bucket. The data comes from a fixed seed, so it's the same every time. To start over, run `.un-local.ps1 -Reset`, which wipes the database, files and gateway together so the books stay balanced.

Every account's password is `password123`. Generated accounts use `@demo.vendra.pk` addresses. The demo accounts are listed on each app's login screen in development:

| Role | Email | Notes |
|---|---|---|
| Admin | admin@vendra.pk | |
| Vendor | usman@vendor.pk | Capital Electronics Hub, Blue Area, Islamabad |
| Vendor | ayesha@vendor.pk | Ayesha's Boutique, Saddar, Rawalpindi |
| Customer | ahmed@customer.pk | F-7, Islamabad |
| Customer | fatima@customer.pk | Satellite Town, Rawalpindi |
| Rider | bilal@rider.pk | G-9, Islamabad |
| Rider | hamza@rider.pk | Saddar, Rawalpindi |

The backend tests use their own small fixture (`tests/fixture.sql`), not this data.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | Postgres connection string |
| `JWT_SECRET` | yes | Signs session tokens — use a long random value in production |
| `PORT` | no | Default `3000` |
| `APP_TIMEZONE` | no | Time zone for "today"/"this week" totals (default `Asia/Karachi`). Timestamps are stored as absolute instants either way |
| `ALLOWED_ORIGINS` | prod | Comma-separated frontend origins allowed by CORS and Socket.IO (e.g. the admin dashboard URL) |
| `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | no | S3-compatible bucket for product photos and dispute evidence. Locally this is SeaweedFS from `docker-compose.yml` (values in `.env.example`); in production, Cloudflare R2 (`S3_REGION=auto`, `S3_FORCE_PATH_STYLE=false`). Without `S3_BUCKET` files are kept on disk |
| `UPLOAD_DIR` | no | Folder used when no bucket is configured (default `./uploads`) |
| `APP_MODE` | no | `development` (default) or `production` — see above |
| `GATEWAY_URL`, `GATEWAY_PUBLIC_URL`, `GATEWAY_PUBLISHABLE_KEY`, `GATEWAY_SECRET_KEY`, `GATEWAY_WEBHOOK_SECRET` | no | The payment gateway (defaults match Vendra Pay in docker-compose). `GATEWAY_PUBLIC_URL` is where the apps reach it, if different |

## Tests

End-to-end tests for every functional requirement (FR01–FR09), card payments, withdrawals, reconciliation, order timeouts and the two modes run against a real Postgres and an in-process Vendra Pay gateway. They create and drop their own database, so point them at a server you don't mind them using:

```bash
TEST_DATABASE_URL=postgresql://postgres:dev@localhost:5432/vendra_it npm test
```

The tests keep photos in a temp folder. Set the `S3_*` variables as well to run them against the bucket instead.

After each money-moving step the tests check that wallets + escrow pool + platform revenue still equal total deposits, and that the escrow pool equals the money held on open orders.

## How it's organised

```
src/
  app.js            Express app + HTTP server + Socket.IO (used by server.js and tests)
  server.js         Starts listening; releases due escrow every 30 s
  realtime.js       Socket.IO rooms and emit helpers
  migrate.js        Migration runner          seed.js   Seed runner
  controllers/      auth, customer, vendor, rider, dispute, account, admin
  services/
    inventory       The only code that changes stock (locks rows in id order)
    orderSettlement Escrow: rider payout, release with commission, refund
    wallet          Wallet credits/debits in SQL
    riderPayout     GPS distance + waiting-time payout
    policy          Admin-editable business rules (read on every use)
    notification    Stored notifications + socket push after commit
    storage         Photo uploads: S3 bucket (SeaweedFS / R2) or local disk
    payments        Card top-ups, card checkout, withdrawals, webhooks, reconciliation
    gateway.client  Talks to the payment gateway (tokens only, never card numbers)
    checkout        Prices the cart and places orders (the only code that creates orders)
    orderTimeouts   Cancels and refunds orders the store or riders never picked up
  config/mode.js    APP_MODE and the development features
  utils/            money (integer paisa), geo (haversine), http (errors, transactions), cors
migrations/         001_init … 006_payments_and_withdrawals
gateway/            Vendra Pay, the payment gateway sandbox (its own Dockerfile and README)
```

Business rules such as the delivery fee, commission, rider rates, geofence radius, task radius, dispute window and default buffer live in the `policies` table and are edited from the admin dashboard; changes apply to the next action without a redeploy.
