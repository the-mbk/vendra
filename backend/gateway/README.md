# Vendra Pay (sandbox)

A local card payment gateway for Vendra, so real money flows (top-ups, card checkout, withdrawals, escrow) can be built and demonstrated without a merchant account. It behaves like a real processor (Stripe-style API) but only accepts test cards.

- No npm dependencies: Node 22.13+ with the built-in SQLite. Data lives in `DATA_DIR` (default `./data`).
- Runs from `../docker-compose.yml` as the `vendra-pay` container, or with `npm run gateway` from `backend/`.
- **Dashboard:** http://localhost:4242 shows the balance, payments, payouts, webhook deliveries and the test cards.

## Test cards

Any future expiry date and any 3-digit CVC. One-time password for 3-D Secure: **123456**.

| Number | Behaviour |
|---|---|
| 4242 4242 4242 4242 | Visa — payment succeeds |
| 5555 5555 5555 4444 | Mastercard — payment succeeds |
| 4000 0566 5566 5556 | Visa debit — payments and payouts succeed |
| 5200 8282 8282 8210 | Mastercard debit — payments and payouts succeed |
| 4000 0027 6000 3184 | Asks for the one-time password |
| 4000 0000 0000 0002 | Declined; payouts to it fail |
| 4000 0000 0000 9995 | Declined: insufficient funds |
| 4000 0000 0000 0069 | Declined: expired card |
| 4000 0000 0000 0127 | Declined: incorrect CVC |
| 4000 0000 0000 0119 | Payments succeed; payouts bounce after processing |

Any other number is refused, so a real card can't be entered by mistake.

## API

Amounts are integer **paisa**, currency `pkr`. Errors are `{ error: { type, code, message } }` (HTTP 402 for card errors).

| Method | Path | Key | Purpose |
|---|---|---|---|
| POST | `/v1/tokens` | publishable | `{ number, exp_month, exp_year, cvc }` → single-use `tok_…` (15 min) |
| POST | `/v1/payment_intents` | secret | `{ amount, token, description?, metadata? }` → `succeeded`, `requires_action` (OTP) or `failed` |
| GET | `/v1/payment_intents/:id` | secret | |
| POST | `/v1/payment_intents/:id/verify` | publishable | `{ otp }` — 3 attempts; unanswered after 15 min → `canceled` |
| POST | `/v1/payouts` | secret | `{ amount, token, description?, metadata? }` → `in_transit`, then `paid` or `failed` after `PAYOUT_DELAY_SEC` |
| GET | `/v1/payouts/:id` | secret | |
| POST | `/v1/topups` | secret | The merchant adds funds to its own balance |
| GET | `/v1/balance` | secret | `{ available, in_transit }` — payments + top-ups − payouts not failed |
| GET | `/v1/test-cards` | none | The table above |

`POST` requests accept an `Idempotency-Key` header: repeating a key returns the first result.

**Webhooks** go to `WEBHOOK_URL` for `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `payout.paid` and `payout.failed`, signed in the header `Vendra-Signature: t=<unix>,v1=<hex HMAC-SHA256 of "t.body" with WEBHOOK_SECRET>`. Failed deliveries are retried with backoff (2 s … 30 min).

## Configuration

| Variable | Default |
|---|---|
| `PORT` | `4242` |
| `DATA_DIR` | `./data` |
| `PUBLISHABLE_KEY` / `SECRET_KEY` / `WEBHOOK_SECRET` | `pk_test_vendra` / `sk_test_vendra` / `whsec_vendra` |
| `WEBHOOK_URL` | none (events wait until it is set) |
| `PAYOUT_DELAY_SEC` | `20` |
