# Vendra Backend

Node.js + Express + PostgreSQL API for Vendra, a multi-vendor marketplace with dual inventory (private vs public stock), atomic order reservation, escrow funded by card payments, rider delivery with GPS payouts, disputes and a policy engine. Realtime updates go over Socket.IO on the same port.

Also: customer reviews and ratings, a 4-digit delivery handover code (so a spoofed GPS position can't complete a delivery), rider document approval, shop staff with PIN switching (cashier / packer / inventory manager), a packing checklist with barcode scanning, product photo galleries, printable POS receipts with a scan-to-pay QR, itemised rider payout slips, security headers and rate limits.

- Card payments go through **Stripe** (test mode) or **Vendra Pay** ([gateway/](gateway/README.md)), a local payment gateway sandbox with test cards, payouts and signed webhooks.
- Withdrawals go to the user's **Payoneer** account (with Stripe), through Payoneer's payouts API or, until Vendra has Payoneer partner credentials, the local [Payoneer simulator](payoneer-sim/README.md).

- API reference: [docs/API.md](docs/API.md)
- Requirements (SRDS): [docs/srds-clean.md](docs/srds-clean.md)

## Requirements

- Node.js 18+ (tests use the built-in `node:test` runner and `fetch`)
- PostgreSQL 16+

## Setup

```bash
npm install
cp .env.example .env        # DATABASE_URL already matches docker-compose.yml; set JWT_SECRET
npm run db:up               # Docker: Postgres (5433), SeaweedFS storage (8333), Vendra Pay gateway (4242), Payoneer simulator (4343)
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

### Stripe instead of Vendra Pay

Set `PAYMENT_PROVIDER=stripe` with your **test** keys in `.env` (`STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`) and restart. Vendra Pay stays the default, and the tests always use it.

- **Card payments:** the apps show Stripe's card field and send a PaymentMethod (`pm_…`); the backend confirms a PaymentIntent in PKR. 3-D Secure runs in the app with Stripe's SDK. Test cards: `4242 4242 4242 4242`, `4000 0025 0000 3155` (3-D Secure), `4000 0000 0000 9995` (declined).
- **Withdrawals (default with Stripe): Payoneer.** Stripe can't pay out to a user's card, and Stripe Connect isn't available to people in Pakistan, so riders, vendors and customers withdraw to their **Payoneer** account (`PAYOUT_PROVIDER=payoneer`):
  1. *Withdraw* → *Link your Payoneer account* opens Payoneer's registration page, where they create a Payoneer account or sign in to theirs and link it to Vendra (once).
  2. Payoneer reviews the account (*pending*), then approves it and tells Vendra by IPCN callback (*active*).
  3. A withdrawal leaves the wallet at once and is sent as a Payoneer payout in USD at `PAYONEER_PKR_PER_USD` rupees per dollar (default 280). It shows *in transit*, then *paid* when Payoneer transfers it, or it fails and the money returns to the wallet.
  4. The money is in their Payoneer balance; from Payoneer they withdraw to their bank in Pakistan. *View Payoneer account* opens it.

  Locally all of this runs against the [Payoneer simulator](payoneer-sim/README.md) (`docker compose` service `payoneer`, dashboard at http://localhost:4343). Its API copies Payoneer's v4 Mass Payouts API as publicly described but hasn't been checked against the partner-only reference; `src/services/payouts/payoneer.js` is the one file to adjust when you get sandbox credentials.
- **Withdrawals, alternative: Stripe Connect** (`PAYOUT_PROVIDER=stripe_connect`). Each user sets up a Stripe Connect **Express** account once (Stripe's hosted page; in test mode use Stripe's test data, e.g. phone `000 000 0000`, SMS code `000000`, SSN `0000`, routing `110000000`, account `000123456789`). A withdrawal is a transfer to that account, in your Stripe account's currency at `STRIPE_PKR_PER_UNIT` rupees per unit (default 280). Connect must be enabled on your Stripe account (Dashboard → Connect → Get started, in test mode). Accounts are created with Stripe's Accounts v2 API (`/v2/core/accounts`, a recipient with the Express dashboard), which new Connect platforms require; onboarding links, status, transfers and dashboard links use the v1 endpoints, which accept those accounts, and payout accounts are created in your Stripe account's country (Stripe doesn't support Pakistani accounts), or `STRIPE_CONNECT_COUNTRY`.
- **Demo money:** wallet balances from the seed never came through Stripe. In development with a test key, when the platform's Stripe balance is too low for a withdrawal it is topped up first with Stripe's `pm_card_bypassPending` test card (recorded in `gateway_fundings`).
- **Webhooks (optional locally):** `stripe listen --forward-to localhost:3000/api/payments/webhook` and put the printed `whsec_…` in `STRIPE_WEBHOOK_SECRET`. Without it, the 30-second sweep picks up payment results.
- **Reconciliation:** Stripe holds the platform's money in its own currency, so Admin → Finance compares every card payment Stripe charged (PKR) with the deposits the books credited, and shows the real Stripe balance next to it.

### File storage

Photos go to an S3-compatible bucket, so local and production use the same code path:

- **Locally:** SeaweedFS (`vendra-storage` container) plays the part of Cloudflare R2. Browse the bucket at http://localhost:8888/buckets/. The bucket is private, like R2: the backend streams product photos at `/uploads/products/<name>` and evidence only through signed links.
- **Production:** point the `S3_*` variables at an R2 bucket. Nothing else changes.
- Photos saved on disk before the bucket existed: `npm run storage:import` copies them in (safe to rerun).

When all the repos sit side by side in one folder, `run-local.ps1` in that folder starts the database, applies migrations, loads demo data into an empty database, and opens the backend, admin dashboard and the three Flutter apps (in Chrome) in their own windows.

### Demo data

`npm run seed` fills an empty database with a marketplace in **Islamabad and Rawalpindi** (development mode only):

- **1,000 users:** 120 stores (about 9 waiting for approval), 150 riders, 729 customers and the admin. Run `npm run seed -- --users=3000` for a bigger city.
- **About 2,000 products:** groceries, electronics, fashion, beauty, home and sports stores, with real product photos (a cover plus up to 3 gallery photos) and some products waiting for approval.
- **90 days of orders:** delivered, cancelled, and recent ones still in escrow. Wallets, rider earnings and platform revenue add up exactly. Deliveries carry their payout slip, and about 40% of delivered orders have customer reviews and a rider rating.
- **Rider applicants:** a few new riders waiting for document review (one sent back), so the admin's review queue isn't empty.
- **Shop staff** at Capital Electronics Hub (usman@vendor.pk), for the vendor app's *Switch user*: Ali Raza (cashier, PIN `1111`), Sana Iqbal (packer, PIN `2222`), Kashif Mehmood (inventory manager, PIN `3333`). The store also has receipt header/footer and a payment account for the scan-to-pay QR.

Product names, descriptions and photos come from [DummyJSON](https://dummyjson.com), a free fake-data API. The first run downloads them into `.cache/`; later runs work offline. The photos go into the file storage bucket. The data comes from a fixed seed, so it's the same every time. To start over, run `.
un-local.ps1 -Reset`, which wipes the database, files and gateway together so the books stay balanced.

Data loaded before migration 010 has no reviews, staff or rider documents; reset to get them. `npm run images:backfill` adds missing product cover photos, gallery photos and store cover photos to an existing database without a reset.

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
| `RATE_LIMIT_MAX` | no | API requests per minute from one IP (default 300; 2000 in development, where all the apps share 127.0.0.1) |
| `LOGIN_RATE_LIMIT_MAX` | no | Failed sign-ins per email per IP in 15 minutes before 429 (default 10) |
| `SIGNUP_RATE_LIMIT_MAX` | no | Sign-ups per IP per hour (default 20) |
| `TRUST_PROXY` | no | Behind a reverse proxy / load balancer, the number of proxy hops (e.g. `1`), so rate limits see the client's IP |

## Tests

End-to-end tests for every functional requirement (FR01–FR09), card payments, withdrawals, reconciliation, order timeouts and the two modes run against a real Postgres and an in-process Vendra Pay gateway. They create and drop their own database, so point them at a server you don't mind them using:

```bash
TEST_DATABASE_URL=postgresql://postgres:dev@localhost:5432/vendra_it npm test
```

The tests keep photos in a temp folder. Set the `S3_*` variables as well to run them against the bucket instead.

After each money-moving step the tests check that wallets + escrow pool + platform revenue still equal total deposits, and that the escrow pool equals the money held on open orders.

`tests/trust-and-operations.test.js` covers reviews, the handover code (wrong codes, lockout), rider approval, staff permissions and PIN lockout, the packing checklist, receipts, galleries, payout slips, security headers and the login rate limit.

### PR 04 benchmark (100 inventory requests per second)

```bash
TEST_DATABASE_URL=postgresql://postgres:dev@localhost:5432/vendra_bench npm run bench:concurrency -- --rate=100 --duration=15
TEST_DATABASE_URL=… npm run bench:concurrency -- --rate=100 --duration=15 --products=10
```

It fires online checkouts at a fixed rate (whether or not earlier ones have answered) while the store sells the same products at the walk-in counter, runs stock out part-way, then checks every number: shelf stock, reserved units vs successful orders vs inventory locks, public stock, the ledger, no overselling, the walk-in buffer untouched, and the money invariants. `--products=1` (default) is the worst case, all requests on one product's row lock; `--products=10` spreads the load. It prints the results and writes `bench/results/concurrency-<time>.json` and an `.html` report with a per-second chart. Like the tests, it drops and recreates the database in `TEST_DATABASE_URL`.

## How it's organised

```
src/
  app.js            Express app + HTTP server + Socket.IO (used by server.js and tests)
  server.js         Starts listening; releases due escrow every 30 s
  realtime.js       Socket.IO rooms and emit helpers
  migrate.js        Migration runner          seed.js   Seed runner
  controllers/      auth, customer, vendor, staff, rider, dispute, account, admin, payment
  middleware/auth   JWT, roles, and shop-staff permissions
  services/
    inventory       The only code that changes stock (locks rows in id order)
    orderSettlement Escrow: rider payout, release with commission, refund
    wallet          Wallet credits/debits in SQL
    riderPayout     GPS distance + waiting-time payout
    policy          Admin-editable business rules (read on every use)
    notification    Stored notifications + socket push after commit
    storage         Photo uploads: S3 bucket (SeaweedFS / R2) or local disk
    payments        Card top-ups, card checkout, withdrawals, webhooks, reconciliation
    gateway.client  The card gateway chosen by PAYMENT_PROVIDER: gateway/vendrapay or gateway/stripe
                    (tokens only, never card numbers)
    payoutAccounts  Where withdrawals go (PAYOUT_PROVIDER): card, Payoneer payee or Stripe Connect account
    payouts/payoneer  Payoneer Mass Payouts client (the only code that knows Payoneer's API)
    checkout        Prices the cart and places orders (the only code that creates orders)
    orderTimeouts   Cancels and refunds orders the store or riders never picked up
    handoverOtp     Delivery handover codes: check, count wrong tries, lock
    review          Customer reviews and the products' running rating totals
    riderDocuments  CNIC / licence / vehicle validation
  config/mode.js    APP_MODE and the development features
  utils/            money (integer paisa), geo (haversine), http (errors, transactions), cors, security (helmet + rate limits)
  backfillImages.js Missing product cover / gallery photos and store covers from the demo catalogue (npm run images:backfill)
migrations/         001_init … 013_store_photos
bench/              PR 04 concurrency benchmark
gateway/            Vendra Pay, the payment gateway sandbox (its own Dockerfile and README)
payoneer-sim/       A local stand-in for Payoneer's payouts API (its own Dockerfile and README)
```

Business rules such as the delivery fee, commission, rider rates, geofence radius, task radius, dispute window and default buffer live in the `policies` table and are edited from the admin dashboard; changes apply to the next action without a redeploy.
