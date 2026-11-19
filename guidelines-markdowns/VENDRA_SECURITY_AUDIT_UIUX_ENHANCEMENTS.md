# Vendra Platform: Security Audit, Anti-Fraud Architecture & UI/UX Governance

> **Project:** Vendra Multi-Vendor Digital Marketplace & Quick-Commerce System
> **Institution:** COMSATS University Islamabad, Wah Campus — Department of Computer Science
> **Purpose:** Security audit, fraud threat model, privacy vs. transparency rules, UI/UX consistency and the admin inspection views, checked against the code.
> **Updated:** November 18, 2026
> **Companion document:** [VENDRA_SYSTEM_IMPROVEMENTS_AND_ABUSE_PREVENTION.md](VENDRA_SYSTEM_IMPROVEMENTS_AND_ABUSE_PREVENTION.md)

---

## 1. Summary

The audit covers all five tiers:

1. **Backend API & realtime server** (Node.js, PostgreSQL, Socket.IO, SeaweedFS, Vendra Pay)
2. **Admin control panel** (Next.js 16, React 19, Tailwind CSS v4)
3. **Customer app** (Flutter web, BLoC, CARTO maps)
4. **Vendor storefront & POS** (Flutter web, real-time inventory)
5. **Rider app** (Flutter web, OSRM routing, geofenced GPS)

| Area | Status | Where it lives |
|---|---|---|
| Admin inspection depth | Done | Order, product and vendor drawers; `GET /api/admin/orders/:id` |
| Fraud & abuse gates | Done | Six gates, tested in `backend/tests/anti-abuse.test.js` |
| Privacy vs. transparency | Done | Server-side rules in `backend/src/utils/privacy.js`, tested in `backend/tests/privacy.test.js` |
| Cross-app UI consistency | Done | One shared theme file, identical in all three Flutter apps |
| Static analysis & tests | Passing | Backend 167/167; Flutter analyzer clean; admin ESLint 0 errors (see §8) |

---

## 2. Admin Panel Inspection Views

### 2.1 Order inspection drawer (`frontend-admin/app/dashboard/orders/page.js`)

**Endpoint:** `GET /api/admin/orders/:id` (`getOrderDetails` in `admin.controller.js`, route in `admin.routes.js`).

Clicking an order number or **Inspect** opens `OrderInspectionModal`:

1. **Summary:**
   - total charged and payment method (card or wallet)
   - escrow state (`held`, `disputed`, `released`, `refunded`) with what it means
   - fulfilment type and kilometres ridden
   - whether the handover code was used
2. **The three parties:**
   - **Customer:** full name, email, and phone masked as `0312-***566`, with a button to reveal it.
   - **Store:** name and shop address.
   - **Rider:** name, masked phone and payout.
3. **Delivery location & handover proof** (delivery orders only):
   - drop-off address, pin coordinates and a link to the pin on OpenStreetMap
   - when the customer's code was entered
   - how many wrong codes were tried, and any active lockout
   - how far the rider stood from the pin at handover, against the geofence, with a link to that point
4. **Timeline:** placed, ready, rider accepted, rider at the store, picked up, delivered. Self-pickup orders show the store and collection steps only.
5. **Money, escrow and settlement:**
   - items subtotal + delivery fee = paid into escrow
   - while the money is held: an *estimate* at today's commission rate
   - after release: the actual figures from the ledgers (commission, store payout, any dispute refund, rider payout, delivery margin)
   - refunded orders show the amount returned to the customer
6. **Items:** photo, name, barcode, unit price × quantity, and line total.

### 2.2 Product drawer (`frontend-admin/app/dashboard/products/page.js`)

Clicking a product name, thumbnail or **Details** opens `ProductDetailModal`:

- **Photo**, with a placeholder when there is none.
- **Identity:**
  - category, barcode (the catalogue's unique product code; there is no separate SKU) and listing date
  - weight in grams as listed by the store, or "Not listed"
- **Four stock figures:**
  - **Shelf:** units physically in the store (`private_stock`).
  - **Walk-in buffer:** units kept back for counter sales.
  - **Online reserved:** units held by open online orders.
  - **Online (public):** `shelf − buffer − reserved`, never below 0. This is what shoppers can buy.
- **Moderation:** approve a pending product, or hide a live one (with a confirmation step).

### 2.3 Vendor drawer (`frontend-admin/app/dashboard/vendors/page.js`)

Clicking a vendor row or **Details** opens `VendorDetailModal`:

- **Store:** name, registration date and verified badge.
- **Owner:** name, CNIC, phone and email.
- **Location:** shop coordinates with an OpenStreetMap link, and the location review status.
- **Activity:**
  - product and sales counts, with a link to that store's products
  - 30-day trust signals: walk-in overrides and counter-code lockouts
- **Actions:** approve or disapprove the store.

---

## 3. Threat Model & Anti-Fraud Gates

| # | Threat | Actor / motive | Vendra defence |
|---|---|---|---|
| 1 | False dispute | Customer wants free goods ("never received") | Escrow freeze (no automatic refund); handover code proof; geofenced handover position; dispute dossier with track records |
| 2 | Phantom delivery | Rider wants the fee without travelling | Customer's 4-digit handover code; delivery geofence (`geofence_m`, default 200 m) |
| 3 | Double-selling | Store sells a unit an online customer reserved | Reservation lock; POS amber conflict modal; explicit, audited override |
| 4 | Counterfeit pickup | Impostor collects an order at the counter | Self-pickup handover needs the code shown only in the customer's app |
| 5 | Money laundering through a store | Stolen cards cashed out via a store wallet | Escrow holds money until delivery plus the dispute window; store CNIC checked at approval; every payout listed in Admin → Withdrawals (there is no manual approval step) |
| 6 | Task hoarding | Rider accepts tasks and stalls | `rider_pickup_timeout_min`: a rider who doesn't reach the store in time loses the task, which goes back to other riders and is recorded |

### 3.1 False dispute

**Scenario:** a customer receives an expensive phone, waits for the rider to leave, then claims "Rider never arrived".

1. **Handover proof:** the customer's app shows a 4-digit code. The rider can only finish with it: `POST /api/rider/orders/:id/deliver { lat, lng, otp }`.
2. **What the server records:** it checks the code and stores `delivered_at`, `otp_verified_at` and the rider's position (`delivery_lat`, `delivery_lng`).
3. **No automatic refund:** a dispute (`POST /api/disputes`) sets escrow to `disputed`. Nothing is refunded until an admin rules, and the release sweep skips disputed orders.
4. **Dossier:** the admin sees:
   - when the code was entered
   - the handover distance from the pin, against the geofence
   - the GPS trail
   - the packing record
   - each party's 30-day track record, including earlier claims and how they ended
   Dismissing the claim (`release`) pays the store; the customer gets nothing back.

### 3.2 Phantom delivery and GPS spoofing

**Scenario:** a rider fakes their GPS to look close to the customer, then marks the order delivered.

1. Even with a spoofed position the rider does not have the customer's code.
2. **Wrong codes:**
   - each wrong code increments `otp_failed_attempts` and returns `422 WRONG_OTP` with `attemptsLeft`
   - after **5** wrong codes the handover locks for **10 minutes** (`otp_locked_until`, `429 OTP_LOCKED`)
   - the customer is notified, and a `handover_lockout` trust event counts against the rider
3. **Geofence:** distance is the Haversine great-circle distance:
   $$d = 2r \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta \text{lat}}{2}\right) + \cos(\text{lat}_1)\cos(\text{lat}_2)\sin^2\left(\frac{\Delta \text{lng}}{2}\right)}\right)$$
   If $d >$ `geofence_m` (admin policy, default 200 m), completion is refused with `422 OUTSIDE_GEOFENCE` `{ distanceMeters, geofenceMeters }`. This check runs before the code is looked at.

### 3.3 POS vs. online order conflict

**Scenario:** one unit of earbuds is left. Customer A buys it online; two minutes later a walk-in customer wants it.

1. **Reservation:** checkout locks the units and raises `products.reserved_quantity` in the same transaction:
   ```sql
   INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES ($1, $2, $3, 'active');
   ```
2. **What the counter can sell:** sellable = `private_stock − reserved_quantity`.
3. **Conflict modal:** when the cashier adds more than that, the POS shows the amber conflict modal. It names the orders holding the units (`GET /api/vendor/products/:id/reservations`, e.g. "Online Order #VDR-00006") and shows the stock figures.
4. **Without an override:** the sale is refused with `409 RESERVED_STOCK` `{ sellable, reserved }`.
5. **Explicit override (only for orders not yet packed):**
   - cancels the newest such order
   - refunds the customer in full and notifies them
   - records a `walk_in_override` against the store, shown to admins

---

## 4. Transparency While Protecting Privacy

These rules are enforced by the server, so a modified app cannot get more than its share.

| Who | Sees | Does not see |
|---|---|---|
| **Customer** | The rider's short name ("Bilal H."). The rider's live position, only while the order is open. The rider's number, only while the order is open. The escrow status badge. | The rider's full name. Where the rider is after delivery. The rider's number after delivery. |
| **Rider, open task** | Store, drop-off address and pin, item count, parcel weight, estimated payout | Any customer name or number, until they accept |
| **Rider, own delivery** | The customer's short name. The number while delivering, shown masked with a Call button. | The customer's full name. The number after delivery. The handover code. Payment details. |
| **Store** | The customer's short name, the basket, and contact numbers while the order is open | The customer's full name, the handover code (only "code required"), payment card details, and the customer's purchases at other stores |
| **Admin** | Full names and numbers (masked until "Show" is clicked), the handover proof, the GPS trail while a dispute can still be raised, and all money movements | Raw card numbers; cards are held only by Vendra Pay (the app keeps only brand and last 4 digits) |

### 4.1 How it is built

1. **Short names** (`shortName` in `backend/src/utils/privacy.js`):
   - customers, stores and riders see each other as "First L."
   - the same helper shortens names on reviews and in dispute views for the parties
   - admins see full names
2. **Numbers only while the order is open** (`contactWhile`):
   - each party gets the other's phone number only while the order is in progress; once it is delivered or cancelled, the number is no longer sent
   - the open task pool sends no customer identity at all
3. **Masked display:** the apps and the admin panel show personal numbers as `0312-***566`:
   - in the apps (`maskPhone` in each app's `core/services/contact_launcher.dart`), only the Call button uses the full number
   - in the admin panel (`MaskedPhone` in `app/lib/ui.js`), the full number appears after a deliberate click
   - there is no telephone proxy, so a rider who places a call does see the number on their own dialler
4. **Location shared only during the delivery:**
   - rider pings are pushed only to sockets watching that order (`track:<orderId>`, owner or admin only) while the rider is on it
   - after delivery the tracking endpoint stops returning the rider's live position
   - the GPS trail is deleted when the escrow settles (`pruneTrip`)
5. **Financial transparency:**
   - the customer sees "Payment held safely in Vendra Escrow" and the release countdown
   - each payout line in the store's wallet shows the calculation, e.g. *"Escrow released for Order #12: items Rs. 6,999 − 10% commission Rs. 699.90 = Rs. 6,299.10"*
   - the admin order drawer shows the same split from the ledgers

---

## 5. UI/UX Consistency

### 5.1 Design tokens

One theme file (`lib/config/app_theme.dart`) is kept identical in the customer, vendor and rider apps.

| Token | Value | Use |
|---|---|---|
| App typography | Google Fonts **Poppins** | All text in the three Flutter apps |
| Admin typography | Google Fonts **Inter** | Data tables and KPI cards |
| Navy | `#232774` (dark mode `#7178EE`) | Brand surfaces, outlined buttons, links |
| Orange | `#FD761A` | Primary buttons, cart, highlights |
| Success | `#16A34A` | Live/approved/delivered, in-stock |
| Warning / escrow | `#F59E0B` | Escrow held, pending, reservations |
| Radius | Cards, dialogs and bottom sheets 16 px; buttons and inputs 12 px; chips 8 px | All three apps |

The navy and orange are the same values as the admin panel (`--primary`, `--secondary-container` in `globals.css`). Dark mode is supported in all three apps and in the admin panel.

### 5.2 Category tiles

The old hand-drawn motif painter has been replaced by squircle tiles: one Material icon on a soft tint of the category colour, filled when selected.

| Category | Icon |
|---|---|
| All | `Icons.dashboard_rounded` |
| Electronics | `Icons.devices_rounded` |
| Mobile accessories | `Icons.headphones_rounded` |
| Fashion | `Icons.checkroom_rounded` |
| Grocery | `Icons.local_grocery_store_rounded` |
| Home & kitchen | `Icons.restaurant_rounded` |
| Health & beauty | `Icons.medical_services_rounded` |
| Books & stationery | `Icons.menu_book_rounded` |

---

## 6. Completed vs. Next Phase

### 6.1 Done

- [x] Admin dark mode built on CSS variables (`globals.css`).
- [x] CARTO basemap key set in one place (`core/widgets/map_tiles.dart`, light and dark styles). It is used by every map: the location picker in all three apps, customer tracking and rider navigation.
- [x] Customer default location: Saddar, Karachi, about 1.1 km from Karachi Electronics Hub.
- [x] Quick location presets in the customer location sheet (development mode only), with the live distance to the nearest store.
- [x] One-tap "set drop-off pin about 1 km from this store" in the cart for out-of-range demos (development mode only).
- [x] Category tiles redesigned.
- [x] Vendor, product and order inspection drawers in the admin panel; `GET /api/admin/orders/:id`.
- [x] Server-side privacy rules: short names, numbers only while an order is open, no customer identity on open tasks, no rider position after delivery.
- [x] Masked phone numbers in the apps and the admin panel.
- [x] Commission breakdown on store wallet lines.
- [x] One shared colour palette and component radius across the admin panel and the three apps.
- [x] SRDS gaps closed (see §7):
  - scan-to-restock (FR01)
  - restock alerts (FR09, Fig 2.11)
  - late cancellation fee and the customer *Cancel order* button (policy engine)
  - admin recent disputes and platform health (Fig 2.9)
  - append-only ledgers in the database (SSR 03)

### 6.2 For the final presentation

1. **Mobile screenshots:** capture each app at 390×844 for the FYP report.
2. **Three-minute demo walkthrough:**
   - *Customer:* adds an item from Karachi Electronics Hub and checks out with escrow protection.
   - *Vendor:* accepts the order, packs it with the scanner checklist and marks it ready.
   - *Rider:* accepts the task, rides the road route and enters the customer's code inside the geofence.
   - *Admin:* inspects the order in the order drawer and checks the escrow settlement in Finance.

---

## 7. SRDS Traceability

Every requirement in the SRDS (`backend/docs/srds-clean.md`), and where it lives. The last column marks the gaps closed in this round.

| SRDS item | Implemented as | New |
|---|---|---|
| FR01 Dual inventory | `public = shelf − buffer − reserved`, recomputed on every stock change (`inventory.service.js`). **Goods received by scanning:** Vendor app → *Stock in* → scan the barcode → enter the units received (`POST /api/vendor/products/:id/stock-in`). An unknown barcode can be added as a new product. | Stock-in |
| FR02 Order reservation | Checkout locks units atomically (`inventory_locks`); the POS conflict modal; `409 RESERVED_STOCK` | |
| FR03 Escrow | Held at checkout; released after delivery and the dispute window; refunded on cancel or dispute | |
| FR04 GPS rider payout | Base + per-km (GPS trail) + paid waiting, from policies; exact to the paisa | |
| FR05 Role-based login | JWT + RBAC for four roles, plus shop staff roles (cashier, packer, inventory manager) | |
| FR06 Catalogue + admin approval | Vendor product form; admin approve/hide; product drawer | |
| FR07 Pick-pack-ready | Packing checklist with barcode scan, then *ready for pickup*, then riders are notified | |
| FR08 Dispute resolution | Photo evidence; escrow frozen; dossier; refund / release / split | |
| FR09 Notifications | In-app and realtime on every order transition. **Restock alerts:** the store is told once when a product's free units reach `low_stock_units`. | Restock alerts |
| §1.3 / §2.3 Policy engine (cancellation, penalty, service, refund rules) | Admin → Policies. **Late cancellation fee** `cancel_penalty_pct`: a pending order cancels free; after the store accepts (before packing) the store keeps that share of the items. The customer app shows the amounts before confirming (*Cancel order* on the tracking screen). | Cancellation fee; customer cancel button |
| Class diagram `Customer.cancelOrder()` | The API existed, but the customer app had no button; now it does | Yes |
| Fig 2.9 Admin dashboard (KPIs, platform health, recent disputes) | KPI grid plus **Recent Disputes** and **Platform Health** (database round trip, escrow pool reconciled against open orders, background job last run, live connections) | Health + disputes panels |
| Fig 2.11 Vendor dashboard (revenue, live orders, quick actions, restock alerts) | Revenue split, active orders, wallet, and the **Restock soon** card with one-tap restock | Restock card |
| PR 01 Inventory sync in 3–5 s | Socket `stock:update` / `stock:vendor` after every commit | |
| PR 02 Reservation < 2 s, PR 04 100 req/s | One transaction with ordered row locks; `bench/inventory-concurrency.js` | |
| PR 03 GPS every 10 s | Rider app pings every 10 s during a delivery | |
| PR 06 Exact money | Integer paisa everywhere; money-invariant checks in the tests | |
| SSR 01 JWT + RBAC, hashed passwords | bcrypt, JWT, per-role routes, staff permissions, login lockout | |
| SSR 02 Escrow released only after GPS-verified delivery | 200 m delivery geofence + the customer's handover code; health panel reconciles the escrow pool | |
| SSR 03 Immutable stock ledger | **Database triggers** (migration 016) refuse UPDATE/DELETE on `inventory_ledger`, `platform_ledger` and `trust_events`. `wallet_ledger` only allows a payout reference to be filled in. Corrections are new entries. | Yes |
| SSR 04 Buffer stock | Per-product buffer (default from policy); online stock never includes it | |

---

## 8. Verification

| Check | Result |
|---|---|
| Backend tests (`npm test`, throwaway database) | 167 / 167 pass, including `srds-completion.test.js` (10), `privacy.test.js` (6) and `anti-abuse.test.js` (11) |
| Flutter `dart analyze` | No issues in customer, vendor and rider |
| Flutter tests (`flutter test --no-pub`) | Customer 86, vendor 87, rider 81: all pass |
| Admin ESLint | 0 errors (2 warnings about the font `<link>` in `layout.js`) |
| Admin `next build` | Succeeds |
| Live API on the dev server | Admin order drawer, rider tasks, customer tracking and store orders all return 200 with the privacy rules applied. The health panel reports escrow reconciled, and editing a ledger row is refused by the database. |

Local services:

| Service | Address |
|---|---|
| Backend health check | `GET http://localhost:3000/api/health` → `{"success": true, ...}` |
| Admin panel | `http://localhost:3001` |
| Customer app | `http://localhost:5001` |
| Vendor app | `http://localhost:5002` |
| Rider app | `http://localhost:5003` |
