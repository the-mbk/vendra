# Vendra Backend

Node.js + Express + PostgreSQL API for Vendra, a multi-vendor marketplace with dual inventory (private vs public stock), atomic order reservation, escrow, rider delivery with GPS payouts, disputes and a policy engine. Realtime updates go over Socket.IO on the same port.

- API reference: [docs/API.md](docs/API.md)
- Requirements (SRDS): [docs/srds-clean.md](docs/srds-clean.md)

## Requirements

- Node.js 18+ (tests use the built-in `node:test` runner and `fetch`)
- PostgreSQL 16+

## Setup

```bash
npm install
cp .env.example .env        # DATABASE_URL already matches docker-compose.yml; set JWT_SECRET
npm run db:up               # local Postgres in Docker on port 5433 (data persists)
npm run migrate             # applies migrations/NNN_*.sql once each
npm run seed                # demo data — empty database only
npm run dev                 # or: npm start
```

The API runs on `http://localhost:3000` (`GET /api/health`). `npm run db:down` stops the database and keeps its data; `docker compose down -v` wipes it.

When all the repos sit side by side in one folder, `run-local.ps1` in that folder starts the database, applies migrations, loads demo data into an empty database, and opens the backend, admin dashboard and the three Flutter apps (in Chrome) in their own windows.

### Demo accounts (password `password123`)

| Role | Email | Notes |
|---|---|---|
| Admin | admin@vendra.pk | |
| Vendor | usman@vendor.pk | Karachi Electronics Hub (Saddar) |
| Vendor | ayesha@vendor.pk | Lahore Fashion Store (Gulberg) |
| Customer | ahmed@customer.pk | Clifton, Karachi |
| Customer | fatima@customer.pk | Model Town, Lahore |
| Rider | bilal@rider.pk | Karachi |
| Rider | hamza@rider.pk | Lahore |

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | Postgres connection string |
| `JWT_SECRET` | yes | Signs session tokens — use a long random value in production |
| `PORT` | no | Default `3000` |
| `NODE_ENV` | no | `production` stops allowing localhost origins |
| `APP_TIMEZONE` | no | Time zone for "today"/"this week" totals (default `Asia/Karachi`). Timestamps are stored as absolute instants either way |
| `ALLOWED_ORIGINS` | prod | Comma-separated frontend origins allowed by CORS and Socket.IO (e.g. the admin dashboard URL) |
| `UPLOAD_DIR` | no | Where dispute photos are stored (default `./uploads`). Hosting disks are usually wiped on redeploy — point this at a persistent volume or swap `src/services/storage.service.js` for object storage |

## Tests

End-to-end tests for every functional requirement (FR01–FR09) run against a real Postgres. They create and drop their own database, so point them at a server you don't mind them using:

```bash
TEST_DATABASE_URL=postgresql://postgres:dev@localhost:5432/vendra_it npm test
```

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
    storage         Dispute evidence uploads
  utils/            money (integer paisa), geo (haversine), http (errors, transactions), cors
migrations/         001_init … 004_complete_functional_requirements
```

Business rules such as the delivery fee, commission, rider rates, geofence radius, task radius, dispute window and default buffer live in the `policies` table and are edited from the admin dashboard; changes apply to the next action without a redeploy.
