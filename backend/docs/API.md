# Vendra API Reference

Base URL: `http://localhost:3000` in development. All responses are JSON shaped `{ success, message?, data? }`.
Errors are `{ success: false, message, code?, ...details }`. Show `message` to the user; branch on `code` when present.

Authenticated routes need `Authorization: Bearer <jwt>`. A missing, expired or invalid token returns 401 with `code` `NO_TOKEN`, `TOKEN_EXPIRED` or `INVALID_TOKEN` — send the user back to sign in. Money values are rupees with 2 decimals. Timestamps are ISO-8601 instants; \"today\"/\"this week\" totals are counted in Asia/Karachi time.

**Pagination:** list endpoints marked *paged* take `?limit=` (default 20, max 100) and `?offset=`, and return `meta: { limit, offset, hasMore, nextOffset }` next to `data`. Fetch the next page with `offset=nextOffset` while `hasMore` is true.

> Vendor routes (`/api/vendor/*`) return **snake_case** database rows (e.g. `private_stock`, `rider_name`).
> Every other route returns **camelCase**. The shared Flutter models parse both.

## Realtime (Socket.IO on the same host/port)

Connect with `{ auth: { token } }` (or no token for public stock updates only). Rooms are joined automatically.

| Event | Who receives it | Payload |
|---|---|---|
| `notification` | the user | `{ id, type, title, body, orderId, isRead, createdAt }` |
| `order:update` | customer, vendor, rider of the order; admins | `{ orderId, status, escrowStatus, riderUserId }` |
| `stock:update` | everyone | `{ productId, vendorId, publicStock }` |
| `stock:vendor` | owning vendor | `{ productId, privateStock, reservedQuantity, buffer, publicStock }` |
| `rider:location` | sockets **tracking** that order (see below), nobody else | `{ orderId, lat, lng, at }` |
| `task:new` | all riders (then call `GET /api/rider/tasks`, which filters by radius) | `{ orderId, vendorId, storeName, storeLat, storeLng }` |
| `task:taken` | all riders | `{ orderId }` |
| `catalog:update` | everyone | `{ productId?, vendorId }` — refetch product lists |
| `config:update` | everyone | `{ keys }` — an admin changed policies; refetch `GET /api/public-config` |

**Live tracking, one order at a time.** A customer can have several deliveries on the road, each rider pinging every 10 s. To get pings, the tracking screen emits `track:order` `{ orderId }` with an ack (`{ ok: true }`, or `{ ok: false, error }` when the order isn't theirs). A socket watches one order at a time: tracking another one replaces it, and `untrack:order` stops. Rooms don't survive a reconnect, so the client re-sends `track:order` after reconnecting. Admins may track any order.

## Auth

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/api/auth/signup` | `{ fullName, email, password, role: customer\|vendor\|rider, phone?, storeName?, cnic? (vendor), vehicleType? (rider) }` | Returns `{ token, user }` |
| POST | `/api/auth/login` | `{ email, password, role? }` | Send the app's role; a mismatch returns **403 `WRONG_APP`** |
| GET | `/api/auth/me` | | User incl. `walletBalance`, `mustChangePassword`, vendor `storeName/isApproved/storeLat/storeLng`, rider `vehicleType/isOnline` |
| POST | `/api/auth/change-password` | `{ currentPassword, newPassword (≥8) }` | 401 `WRONG_PASSWORD` if the current one is wrong. Clears `mustChangePassword` |

Login also returns `user.mustChangePassword`: when true (an admin issued a temporary password) the app should make the user choose a new one before continuing. There is no self-service "forgot password" (no email/SMS service); an admin resets it from the dashboard.

## Public

| Method | Path | Notes |
|---|---|---|
| GET | `/api/public-config?role=` | Read at app start. `{ mode: development\|production, features: { manualLocation, testCards, fastTimers, demoLogin }, deliveryFee (base), deliveryFeePerKm, maxDeliveryKm (0 = no limit), disputeWindowMinutes, geofenceMeters, taskRadiusKm, defaultBuffer, vendorAcceptTimeoutMinutes, riderAssignTimeoutMinutes, payments: { gatewayUrl, publishableKey, minTopup, maxTopup, minWithdrawal }, demoAccounts: [{ role, name, email, password, note }] }`. `demoAccounts` is empty in production; `?role=` narrows it to one app. Timing values are the effective ones (capped in development) |
| GET | `/api/categories` | `[{ id, name, icon }]` (icon is a Material icon name) |
| GET | `/api/products?search=&vendor_id=&category_id=` | *Paged.* Approved, in-stock products from approved vendors. `search` matches the product name, description or store name. Includes `categoryId`, `categoryName`, `publicStock`, `imageUrl` (public path like `/uploads/products/x.jpg`, or null), `vendorLat/Lng` |
| GET | `/api/vendors/:id` | Store + its products |
| GET | `/api/stores?lat=&lng=&search=` | Every approved store with a location and something in stock, for the map and store search (`search` matches the store name or address): `[{ id, storeName, storeAddress, latitude, longitude, productCount, distanceKm, deliversToYou }]`. With `lat/lng`: nearest first, with `distanceKm` and `deliversToYou` (within `maxDeliveryKm`) |

## Customer (role `customer`)

| Method | Path | Body / notes |
|---|---|---|
| POST | `/api/customer/checkout/quote` | Same body as checkout → `{ subtotal, deliveryFee, total, distanceKm, vendorId }`: exactly what checkout will charge now. Same errors as checkout (409 `INSUFFICIENT_STOCK`, 400 `OUT_OF_DELIVERY_RANGE` `{ distanceKm, maxDeliveryKm }` …). Call it whenever the cart, delivery type or pin changes |
| POST | `/api/customer/checkout` | `{ items: [{ productId, quantity }], deliveryType: delivery\|self_pickup, deliveryAddress?, customerLat, customerLng }`. **Delivery orders require the lat/lng pin** (the rider's 200 m geofence checks against it). Errors: 409 `INSUFFICIENT_STOCK` `{ productId, available }`, 400 `INSUFFICIENT_BALANCE`. Returns `{ id, status, subtotal, deliveryFee, totalAmount, walletBalance, escrowStatus, items }` |
| GET | `/api/customer/orders/:id` | One order (same shape) — use it to refresh after an `order:update` event |
| GET | `/api/customer/orders?scope=active\|past` | *Paged*, newest first. `active` = not delivered or cancelled. `meta.activeCount` is always the number of active orders. Orders incl. `subtotal, deliveryFee, escrowStatus (held\|disputed\|released\|refunded), escrowReleaseDueAt, rider {id,name,phone}, latestDispute {id,status,resolution,issueType}, customerLat/Lng, vendorLat/Lng, assignedAt, pickedAt, deliveredAt` |
| GET | `/api/customer/orders/:id/tracking` | `{ order, riderLocation {lat,lng,at} \| null, path: [{lat,lng,at}] }` |
| POST | `/api/customer/orders/:id/cancel` | Pending orders only (409 otherwise) — full refund, stock released |
| POST | `/api/customer/orders/:id/picked-up` | Self pickup: ready_for_pickup → picked |
| POST | `/api/customer/orders/:id/confirm-received` | Self pickup: → delivered, starts the dispute window |

## Card payments and withdrawals

Money enters Vendra only through the card gateway and leaves only through card payouts. The apps **never send card numbers to this API**: they tokenize the card directly at the gateway and send the single-use token.

**Tokenize (app → gateway):** `POST {payments.gatewayUrl}/v1/tokens` with header `Authorization: Bearer {payments.publishableKey}` and body `{ number, exp_month, exp_year, cvc }` → `{ id: "tok_…", card: { brand, last4, funding, exp_month, exp_year } }`. Errors are `402 { error: { code, message } }` (`incomplete_number`, `invalid_number`, `test_card_required`, `invalid_expiry_month`, `invalid_expiry_year`, `incomplete_cvc`) — show `message`. Tokens are single-use and expire after 15 minutes. If the gateway URL's host is `localhost`, use the API's host instead (emulators and phones). Test cards: `GET {gatewayUrl}/v1/test-cards` (no key needed), shown only when `features.testCards` is on.

**One-time password (3-D Secure):** when a payment comes back with `status: requires_action`, ask for the code and send it straight to the gateway: `POST {gatewayUrl}/v1/payment_intents/{payment.gatewayIntentId}/verify` with the publishable key and `{ otp }`. A wrong code returns `402 incorrect_otp` with the attempts left in `message`; after 3 wrong codes the payment fails. Then call `POST /api/payments/:id/refresh`.

| Method | Path | Who | Body / notes |
|---|---|---|---|
| POST | `/api/payments/topup` | customer | `{ amount (Rs 100–500,000), token }` → `{ payment, order: null, walletBalance }`. A declined card returns **402** with the same shape and `message` |
| POST | `/api/payments/checkout` | customer | The `/api/customer/checkout` body plus `token`. The cart is checked first (409 `INSUFFICIENT_STOCK` etc. **before** the card is charged), the card is charged the exact total, then the order is placed → `{ payment, order, walletBalance }`. If the order can't be placed after payment (stock sold out during the OTP step), `payment.orderError` says why and the money stays in the wallet |
| GET | `/api/payments` | any | *Paged.* The user's card payments |
| GET | `/api/payments/:id` | owner | One payment |
| POST | `/api/payments/:id/refresh` | owner | Re-reads it from the gateway → `{ payment, order, walletBalance }`. Call after the OTP step |
| POST | `/api/withdrawals` | any | `{ amount (≥ payments.minWithdrawal), token }` → `{ withdrawal, walletBalance }`. The wallet is debited at once; the payout lands on the card after a short delay (`in_transit` → `paid`), or bounces (`failed`) and the money returns to the wallet. 400 `INSUFFICIENT_BALANCE`, `AMOUNT_OUT_OF_RANGE` |
| GET | `/api/withdrawals` | any | *Paged.* The user's withdrawals |

`payment`: `{ id, purpose: topup|checkout, amount, status: processing|requires_action|succeeded|failed|canceled, card: { brand, last4 }, gatewayIntentId, nextAction: { type: "otp", attemptsLeft, hint } | null, failureMessage, orderId, orderError, createdAt }`. `hint` (the sandbox code) is only sent in development mode.
`withdrawal`: `{ id, amount, status: pending|in_transit|paid|failed, card: { brand, last4 }, gatewayPayoutId, failureMessage, createdAt, settledAt }`.
Other codes: 400 `CARD_TOKEN_REQUIRED`, 400 `TOKEN_ALREADY_USED` / `TOKEN_EXPIRED` (enter the card again), 503 `GATEWAY_UNAVAILABLE`.

`POST /api/payments/webhook` receives the gateway's signed events (`Vendra-Signature: t=…,v1=HMAC-SHA256(secret, "t.body")`); it is not for the apps.

## Vendor (role `vendor`)

| Method | Path | Body / notes |
|---|---|---|
| GET | `/api/vendor/products` | Rows incl. `private_stock, buffer, reserved_quantity, public_stock, category_id, category_name, is_approved` |
| POST | `/api/vendor/products` | `{ name, price, private_stock, description?, buffer? (defaults to policy), barcode?, category_id? }`. New products have `is_approved=false` until an admin approves (unless the auto-approve policy is on) |
| PUT | `/api/vendor/products/:id` | Any of the create fields. 409 `BELOW_RESERVED` `{ reserved }` if private stock would go below reserved units |
| DELETE | `/api/vendor/products/:id` | 409 while units are reserved |
| GET | `/api/vendor/products/barcode/:code` | Scan lookup; 404 if not in this store |
| POST | `/api/vendor/products/:id/image` | multipart, one image in field `image` (≤5 MB; JPEG/PNG/WebP/HEIC). Replaces any existing photo; returns the product row with `image_url` |
| DELETE | `/api/vendor/products/:id/image` | Removes the photo |
| POST | `/api/vendor/pos/sales` | Walk-in sale `{ items: [{ productId, quantity }] }`. Sellable = `private_stock − reserved_quantity` (buffer can be sold, reserved units cannot). 409 `RESERVED_STOCK` `{ productId, sellable, reserved }`. Returns `{ id, total_amount, items: [{ product_id, product_name, quantity, unit_price, private_stock_after, public_stock_after, reserved_quantity }] }` |
| GET | `/api/vendor/pos/sales` | Today: `{ sales, today_count, today_total }` |
| GET | `/api/vendor/orders/:id` | One order (same row shape) — refresh after an `order:update` event |
| GET | `/api/vendor/orders?scope=active\|history\|all` | `active`: every in-progress order, not paged. `history` (delivered/cancelled) and `all` (default): *paged*, default 30. Rows incl. `items, customer_name, customer_phone, rider_name, rider_phone, escrow_status, subtotal, delivery_fee, latest_dispute` |
| PUT | `/api/vendor/orders/:id/approve` | pending → confirmed |
| PUT | `/api/vendor/orders/:id/reject` | pending → cancelled (refund + stock released) |
| PUT | `/api/vendor/orders/:id/prepare` | confirmed → packed |
| PUT | `/api/vendor/orders/:id/ready-for-pickup` | packed → ready_for_pickup. Delivery orders are broadcast to riders within the task radius |
| PUT | `/api/vendor/orders/:id/deliver` | Self pickup only: → delivered, starts the dispute window |
| PUT | `/api/vendor/location` | `{ latitude, longitude, storeAddress? }`. A store waiting for approval moves straight away (200, `data.applied: true`). An approved store files a request instead (202, `applied: false`): it stays at its current location until an admin approves. A new request replaces an earlier one. `data` carries `latitude, longitude, storeAddress, pendingLocation, locationRejectionReason` (also on `/api/auth/me`) |
| DELETE | `/api/vendor/location/request` | Withdraw a location change waiting for review |
| GET | `/api/vendor/inventory/ledger` | `change_type`: `stock_in, adjustment, reserve, release, sale (online delivered), pos_sale (walk-in)` |

## Rider (role `rider`)

| Method | Path | Body / notes |
|---|---|---|
| GET | `/api/rider/profile` | `{ isOnline, vehicleType, currentLat, currentLng, lastLocationAt, activeOrderId }` |
| PUT | `/api/rider/status` | `{ isOnline, lat?, lng? }`. 409 `ACTIVE_DELIVERY` if going offline with an active delivery |
| POST | `/api/rider/location` | `{ lat, lng, source?: gps\|manual }` — send **every 10 s while online**. Returns `{ orderId }` of the active delivery (or null). `source: manual` (a position set by hand or a simulated drive) is accepted only when `features.manualLocation` is on, else **403 `MANUAL_LOCATION_DISABLED`**. `PUT /api/rider/status` takes the same `source` |
| GET | `/api/rider/tasks` | `{ tasks, activeOrderId, reason? (offline\|busy\|no_location), radiusKm }`. Task: `{ id, storeName, storeAddress, storeLat/Lng, deliveryAddress, customerLat/Lng, itemCount, distanceToStoreKm, tripDistanceKm, estimatedPayout, readyAt }` |
| POST | `/api/rider/tasks/:id/accept` | First rider wins; 409 `TASK_TAKEN` otherwise. One active delivery at a time |
| GET | `/api/rider/orders?scope=active\|history` | `history` is *paged*. Rider orders incl. `storePhone, customerName, customerPhone, distanceKm, waitMinutes, payout` |
| POST | `/api/rider/orders/:id/arrived` | `{ lat, lng }`. At the store (waiting time starts). 422 `OUTSIDE_PICKUP_GEOFENCE` `{ distanceMeters, geofenceMeters }` unless within `pickup_geofence_m` of the store |
| POST | `/api/rider/orders/:id/picked` | `{ lat, lng }`. ready_for_pickup → picked, with the same store check |
| POST | `/api/rider/orders/:id/on-the-way` | picked → on_the_way |
| POST | `/api/rider/orders/:id/deliver` | `{ lat, lng }` — must be within the geofence (200 m) of the customer pin, else **422 `OUTSIDE_GEOFENCE` `{ distanceMeters, geofenceMeters }`**. Returns `{ distanceKm, distanceSource (gps\|straight_line), waitMinutes, payout }` |
| GET | `/api/rider/earnings` | `{ today, todayCount, week, weekCount, allTime, allTimeCount, totalKm, walletBalance, recent }` |

Payout = `rider_base_fee + rider_per_km × GPS km + rider_per_wait_min × max(0, wait − rider_free_wait_min)`.

Delivery fee (charged to the customer) = `delivery_fee + delivery_fee_per_km × straight-line km from the store to the customer pin`, rounded to the nearest Rs 10. Self pickup is free. Stores farther than `max_delivery_km` (default 15) from the pin don't deliver: checkout and quote return **400 `OUT_OF_DELIVERY_RANGE`**; self pickup still works. One order is always from one store, so the apps keep a separate cart per store.

## Any signed-in user

| Method | Path | Notes |
|---|---|---|
| GET | `/api/notifications?limit=50` | `{ notifications, unreadCount }` |
| PUT | `/api/notifications/read-all` | |
| PUT | `/api/notifications/:id/read` | |
| GET | `/api/wallet?limit=50` | Max 200. `{ balance, transactions: [{ id, orderId, type, amount, balanceAfter, description, reference, createdAt }] }`. `type`: `deposit` (card payment, `reference` = `pi_…`), `opening_balance` (money from before the gateway), `escrow_hold`, `escrow_refund`, `escrow_release`, `rider_payout`, `withdrawal` (`reference` = `po_…` once sent), `withdrawal_reversal` |
| POST | `/api/disputes` | **multipart/form-data**: `orderId, issueType, description (≥10 chars)`, up to 4 image files in field `evidence` (≤5 MB each). Party to the order only; escrow must still be `held`. `issueType`: `item_not_received, damaged_item, wrong_item, missing_items, quality_issue, rider_issue, customer_issue, other` |
| GET | `/api/disputes/mine` | Disputes on the user's orders |
| GET | `/api/disputes/:id` | `{ id, orderId, issueType, description, status, resolution, adminNote, raisedBy {id,name,role}, order {status, escrowStatus, totalAmount, heldAmount, storeName, customerName, riderName}, evidence: [{id, url, name}] }`. `url` is a signed link like `/api/files/evidence/x.jpg?exp=…&sig=…`, valid for about an hour — prefix the base URL; don't store it, fetch the dispute again for fresh links |

## Admin (role `admin`)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/admin/stats` | + `ridersOnline, pendingProducts, openDisputes, platformRevenue, orders.inProgress` |
| GET | `/api/admin/vendors` · PUT `/:id/approve` · PUT `/:id/disapprove` | Rows include `latitude, longitude, pendingLocation: { latitude, longitude, address, requestedAt, movedKm } \| null` |
| PUT | `/api/admin/vendors/:id/location/approve` · `/location/reject` `{ reason }` | Review a store's location change: approve moves the store; reject (reason required) leaves it where it is. Either way the vendor is notified. 409 when nothing is waiting |
| GET | `/api/admin/products?status=pending\|approved\|all` · PUT `/:id/approve` · PUT `/:id/hide` | Catalog approval |
| GET | `/api/admin/policies` | `[{ key, value, effectiveValue, label, unit, description, updatedAt }]`. `effectiveValue` differs from `value` only in development mode, where fast timers cap the dispute window (2 min), store response time (5 min) and rider search time (10 min) |
| PUT | `/api/admin/policies` | `{ values: { key: number } }`. `%` ≤ 100, `0/1` flags, `units` whole numbers |
| GET | `/api/admin/disputes?status=open\|resolved` | Same shape as `GET /api/disputes/:id` |
| PUT | `/api/admin/disputes/:id/resolve` | `{ resolution: refund\|release, note? }` |
| GET | `/api/admin/riders` | `{ fullName, email, phone, vehicleType, isOnline, deliveries, earnings, walletBalance, activeOrderId }` |
| GET | `/api/admin/finance` | `{ escrowPool, held {orders, amount}, disputed {orders, amount}, commission, deliveryMargin, platformRevenue, riderPayouts, recent }` |
| GET | `/api/admin/finance/reconciliation` | Does the money at the gateway match the books? `{ gateway: { reachable, available, inTransit }, books: { wallets, escrow, platformRevenue, pendingWithdrawals, uncreditedPayments }, openingBalances: { total, funded, unfunded }, expectedGatewayBalance, difference, balanced }` |
| GET | `/api/admin/payments?status=&search=` · `/api/admin/withdrawals?status=&search=` | *Paged*, default 50. `search` matches the user's name or email, the gateway id, the card's last 4 digits and (payments) the order number, e.g. `#VDR-03630`. The payment/withdrawal shapes above plus `user: { id, name, email, role }` |
| GET | `/api/admin/orders` · `/api/admin/users` | Orders incl. `escrowStatus, deliveryType, riderName, riderPayout, paymentMethod (wallet\|card), cancellationReason` |
| PUT | `/api/admin/users/:id/reset-password` | Sets a random 10-character temporary password and returns it once as `data.temporaryPassword`; the user must change it at next sign-in. Not allowed for admin accounts |

## Order and escrow lifecycle

```
pending ─approve→ confirmed ─prepare→ packed ─ready→ ready_for_pickup
   │                                                   │
   └─reject/cancel→ cancelled (refund)                  ├─ delivery:  rider accept → picked → on_the_way → delivered (geofenced)
                                                       └─ self pickup: picked (optional) → delivered

escrow: held ──(delivered + dispute window, no dispute)──→ released (vendor gets subtotal − commission)
          └─ dispute opened → disputed ─admin→ refunded (customer) | released
rider payout leaves escrow at delivery time.

automatic: pending longer than vendor_accept_timeout_min            → cancelled, refunded ("Store didn't respond in time")
           ready_for_pickup (delivery) with no rider after rider_assign_timeout_min → cancelled, refunded ("No rider available")

money:  card ─gateway→ wallet (deposit) ─checkout→ escrow ─release→ vendor/rider wallets ─withdrawal→ card
```
