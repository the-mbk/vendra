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
| `rider:location` | customer of the active order | `{ orderId, lat, lng, at }` |
| `task:new` | all riders (then call `GET /api/rider/tasks`, which filters by radius) | `{ orderId, vendorId, storeName, storeLat, storeLng }` |
| `task:taken` | all riders | `{ orderId }` |
| `catalog:update` | everyone | `{ productId?, vendorId }` — refetch product lists |

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
| GET | `/api/public-config` | `{ deliveryFee, disputeWindowMinutes, geofenceMeters, taskRadiusKm, defaultBuffer }` |
| GET | `/api/categories` | `[{ id, name, icon }]` (icon is a Material icon name) |
| GET | `/api/products?search=&vendor_id=&category_id=` | *Paged.* Approved, in-stock products from approved vendors. Includes `categoryId`, `categoryName`, `publicStock`, `imageUrl` (public path like `/uploads/products/x.jpg`, or null), `vendorLat/Lng` |
| GET | `/api/vendors/:id` | Store + its products |

## Customer (role `customer`)

| Method | Path | Body / notes |
|---|---|---|
| POST | `/api/customer/checkout` | `{ items: [{ productId, quantity }], deliveryType: delivery\|self_pickup, deliveryAddress?, customerLat, customerLng }`. **Delivery orders require the lat/lng pin** (the rider's 200 m geofence checks against it). Errors: 409 `INSUFFICIENT_STOCK` `{ productId, available }`, 400 `INSUFFICIENT_BALANCE`. Returns `{ id, status, subtotal, deliveryFee, totalAmount, walletBalance, escrowStatus, items }` |
| GET | `/api/customer/orders/:id` | One order (same shape) — use it to refresh after an `order:update` event |
| GET | `/api/customer/orders` | *Paged*, newest first. Orders incl. `subtotal, deliveryFee, escrowStatus (held\|disputed\|released\|refunded), escrowReleaseDueAt, rider {id,name,phone}, latestDispute {id,status,resolution,issueType}, customerLat/Lng, vendorLat/Lng, assignedAt, pickedAt, deliveredAt` |
| GET | `/api/customer/orders/:id/tracking` | `{ order, riderLocation {lat,lng,at} \| null, path: [{lat,lng,at}] }` |
| POST | `/api/customer/orders/:id/cancel` | Pending orders only (409 otherwise) — full refund, stock released |
| POST | `/api/customer/orders/:id/picked-up` | Self pickup: ready_for_pickup → picked |
| POST | `/api/customer/orders/:id/confirm-received` | Self pickup: → delivered, starts the dispute window |
| POST | `/api/customer/wallet/topup` | `{ amount }` — simulated deposit |

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
| PUT | `/api/vendor/location` | `{ latitude, longitude, storeAddress? }` |
| GET | `/api/vendor/inventory/ledger` | `change_type`: `stock_in, adjustment, reserve, release, sale (online delivered), pos_sale (walk-in)` |

## Rider (role `rider`)

| Method | Path | Body / notes |
|---|---|---|
| GET | `/api/rider/profile` | `{ isOnline, vehicleType, currentLat, currentLng, lastLocationAt, activeOrderId }` |
| PUT | `/api/rider/status` | `{ isOnline, lat?, lng? }`. 409 `ACTIVE_DELIVERY` if going offline with an active delivery |
| POST | `/api/rider/location` | `{ lat, lng }` — send **every 10 s while online**. Returns `{ orderId }` of the active delivery (or null) |
| GET | `/api/rider/tasks` | `{ tasks, activeOrderId, reason? (offline\|busy\|no_location), radiusKm }`. Task: `{ id, storeName, storeAddress, storeLat/Lng, deliveryAddress, customerLat/Lng, itemCount, distanceToStoreKm, tripDistanceKm, estimatedPayout, readyAt }` |
| POST | `/api/rider/tasks/:id/accept` | First rider wins; 409 `TASK_TAKEN` otherwise. One active delivery at a time |
| GET | `/api/rider/orders?scope=active\|history` | `history` is *paged*. Rider orders incl. `storePhone, customerName, customerPhone, distanceKm, waitMinutes, payout` |
| POST | `/api/rider/orders/:id/arrived` | At the store (waiting time starts) |
| POST | `/api/rider/orders/:id/picked` | ready_for_pickup → picked |
| POST | `/api/rider/orders/:id/on-the-way` | picked → on_the_way |
| POST | `/api/rider/orders/:id/deliver` | `{ lat, lng }` — must be within the geofence (200 m) of the customer pin, else **422 `OUTSIDE_GEOFENCE` `{ distanceMeters, geofenceMeters }`**. Returns `{ distanceKm, distanceSource (gps\|straight_line), waitMinutes, payout }` |
| GET | `/api/rider/earnings` | `{ today, todayCount, week, weekCount, allTime, allTimeCount, totalKm, walletBalance, recent }` |

Payout = `rider_base_fee + rider_per_km × GPS km + rider_per_wait_min × max(0, wait − rider_free_wait_min)`.

## Any signed-in user

| Method | Path | Notes |
|---|---|---|
| GET | `/api/notifications?limit=50` | `{ notifications, unreadCount }` |
| PUT | `/api/notifications/read-all` | |
| PUT | `/api/notifications/:id/read` | |
| GET | `/api/wallet?limit=50` | Max 200. `{ balance, transactions: [{ id, orderId, type, amount, balanceAfter, description, createdAt }] }` |
| POST | `/api/disputes` | **multipart/form-data**: `orderId, issueType, description (≥10 chars)`, up to 4 image files in field `evidence` (≤5 MB each). Party to the order only; escrow must still be `held`. `issueType`: `item_not_received, damaged_item, wrong_item, missing_items, quality_issue, rider_issue, customer_issue, other` |
| GET | `/api/disputes/mine` | Disputes on the user's orders |
| GET | `/api/disputes/:id` | `{ id, orderId, issueType, description, status, resolution, adminNote, raisedBy {id,name,role}, order {status, escrowStatus, totalAmount, heldAmount, storeName, customerName, riderName}, evidence: [{id, url, name}] }`. `url` is a signed link like `/api/files/evidence/x.jpg?exp=…&sig=…`, valid for about an hour — prefix the base URL; don't store it, fetch the dispute again for fresh links |

## Admin (role `admin`)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/admin/stats` | + `ridersOnline, pendingProducts, openDisputes, platformRevenue, orders.inProgress` |
| GET | `/api/admin/vendors` · PUT `/:id/approve` · PUT `/:id/disapprove` | |
| GET | `/api/admin/products?status=pending\|approved\|all` · PUT `/:id/approve` · PUT `/:id/hide` | Catalog approval |
| GET | `/api/admin/policies` | `[{ key, value, label, unit, description, updatedAt }]` |
| PUT | `/api/admin/policies` | `{ values: { key: number } }`. `%` ≤ 100, `0/1` flags, `units` whole numbers |
| GET | `/api/admin/disputes?status=open\|resolved` | Same shape as `GET /api/disputes/:id` |
| PUT | `/api/admin/disputes/:id/resolve` | `{ resolution: refund\|release, note? }` |
| GET | `/api/admin/riders` | `{ fullName, email, phone, vehicleType, isOnline, deliveries, earnings, walletBalance, activeOrderId }` |
| GET | `/api/admin/finance` | `{ escrowPool, held {orders, amount}, disputed {orders, amount}, commission, deliveryMargin, platformRevenue, riderPayouts, recent }` |
| GET | `/api/admin/orders` · `/api/admin/users` | Orders incl. `escrowStatus, deliveryType, riderName, riderPayout` |
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
```
