# Payoneer sandbox simulator

A local stand-in for Payoneer's Mass Payouts API, so Vendra's withdrawals to Payoneer can be built, tested and demoed before Vendra has Payoneer partner credentials. No npm dependencies (Node 22.13+, built-in SQLite).

```bash
docker compose up -d payoneer     # from backend/ (also started by npm run db:up)
# or: npm run payoneer            # runs it on the host
```

- **Program dashboard:** http://localhost:4343 shows the program balance ($1,000,000 to start), payees, payouts and the callbacks sent to Vendra.
- **A payee's own page:** http://localhost:4343/payee/vendra-<user id> shows their Payoneer balance and the payments received from Vendra (what "View Payoneer account" opens).

## What it does

| Step | Endpoint |
|---|---|
| Vendra signs in | `POST /api/v2/oauth2/token` (HTTP Basic client id:secret, `grant_type=client_credentials`) → `access_token` |
| Registration page for a user | `POST /v4/programs/{program}/payees/registration-link` `{ payee_id, redirect_url, payee: { contact } }` → `result.registration_link` |
| The user signs up or links an existing account | `GET /partners/sign-up?token=…` (a form, any password); afterwards the browser goes to `redirect_url` |
| Payee status | `GET /v4/programs/{program}/payees/{payee_id}/status` → `result.status.type`: `PENDING` → `ACTIVE` after `APPROVAL_DELAY_SEC` |
| Pay out | `POST /v4/programs/{program}/masspayouts` `{ Payments: [{ client_reference_id, payee_id, amount (USD, decimal), currency, description }] }`; resending a reference does nothing |
| Payout status | `GET /v4/programs/{program}/payouts/{client_reference_id}/status` → `Pending` → `Transferred` after `PAYOUT_DELAY_SEC` (or `Failed`) |
| Program balance | `GET /v4/programs/{program}/balance` |
| Notifications (IPCN) | `GET {IPCN_URL}&APPROVED&apuid=…` when a payee is approved, `…&PAYMENT&paymentid=…&status=…` when a payout settles |

Payees whose email contains `+fail` are approved, but payouts to them fail, so you can see a withdrawal returned to the wallet.

## Settings

| Variable | Default |
|---|---|
| `PORT` | 4343 |
| `CLIENT_ID` / `CLIENT_SECRET` / `PROGRAM_ID` | `vendra_sandbox` / `vendra_sandbox_secret` / `100086` (match the backend's defaults) |
| `IPCN_URL` | where to send notifications, e.g. `http://host.docker.internal:3000/api/payouts/payoneer/ipcn?token=ipcn_vendra` |
| `PUBLIC_URL` | the address browsers use for the registration page (`http://localhost:4343`) |
| `APPROVAL_DELAY_SEC` / `PAYOUT_DELAY_SEC` | 8 / 15 |
| `DATA_DIR` | `./data` (`/data` in Docker) |

## Switching to the real Payoneer

Payoneer's API reference is only available to approved partners, so the paths, fields and status names above follow Payoneer's v4 Mass Payouts API as it is publicly described. **They have not been checked against the real reference.** Everything Payoneer-specific in the backend is in `src/services/payouts/payoneer.js`. Once you have sandbox credentials:

1. Compare that file with Payoneer's reference and adjust it.
2. Set `PAYONEER_API_URL`, `PAYONEER_AUTH_URL`, `PAYONEER_CLIENT_ID`, `PAYONEER_CLIENT_SECRET`, `PAYONEER_PROGRAM_ID` and `PAYONEER_PAYEE_PORTAL` in the backend's `.env`.
3. Register `{PUBLIC_API_URL}/api/payouts/payoneer/ipcn?token=<PAYONEER_IPCN_TOKEN>` as the IPCN URL with Payoneer, and allow-list Payoneer's IP addresses (its callbacks are not signed).
