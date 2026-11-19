# Vendra Platform: Improvements, Anti-Abuse Architecture & Implementation Specification

> **Project:** Vendra Multi-Vendor Digital Marketplace & Quick-Commerce System  
> **Institution:** COMSATS University Islamabad, Wah Campus — Department of Computer Science  
> **Document Purpose:** Audit of implemented features, the anti-abuse safeguards, map and self-pickup workflows, UI/UX consistency, and ready-to-run prompts.  
> **Generated Date:** November 18, 2026 (audited against the code and updated the same day)

---

## 1. Executive Status Summary

| # | Requested Area | Status | Key Deliverable / Files Changed |
|---|---|---|---|
| **1** | **Admin Dark/Light Mode & Vendor Enhancements** | **COMPLETED** | `globals.css` CSS-variable tokens with dark overrides; `VendorDetailModal` in `dashboard/vendors/page.js` with owner/CNIC details, OSM link, approve/disapprove, a store-filtered product link and 30-day trust signals. |
| **2** | **Saved Locations Proximity, Store Pins & Self-Pickup** | **COMPLETED** | CARTO basemap (key in one file, `core/widgets/map_tiles.dart`, dark tiles in dark mode); default pin in Saddar, Karachi; every store pinned on the location picker; development-only demo presets and "pin near this store" shortcut; self-pickup directions. |
| **3** | **Category Chips Redesign & Performance** | **COMPLETED** | Squircle category tiles (`custom_category_chip.dart`); production build commands corrected (§4, Prompt A). |
| **4** | **Anti-Abuse & Anti-Fraud Edge Case Guards** | **COMPLETED** | All 6 gates enforced server-side, plus an audit trail (`trust_events`, migration 015) shown to the admin; 11 end-to-end tests in `backend/tests/anti-abuse.test.js`. |
| **5** | **Unified Typography & Premium UI/UX Polish** | **COMPLETED** | Poppins across the 3 Flutter apps (Roboto Mono only for card numbers); Inter on Admin; no emoji in UI copy. |

---

## 2. Detailed Breakdown of Implemented Changes

### 2.1 Point 1: Admin Panel Dark/Light Mode & Vendor Enhancements
* **Issue Addressed:** Clicking the sun/moon toggle switched the icon, but cards, background, sidebar and inputs stayed white because Tailwind CSS v4 inlined static hex values from the `@theme` block.
* **Implementation in `frontend-admin/app/globals.css`:**
  - Colour tokens are CSS variables in `:root`, redefined under `.dark` (`--background`, `--surface-container-lowest`, `--on-surface`, `--outline`, …).
  - `@theme` maps to `var(--…)`, so utility classes follow the class on `<html>`; tinted status backgrounds (`*-50`) become translucent in dark mode.
  - The saved theme is applied before first paint, so there is no white flash.
* **Vendor Details Modal in `frontend-admin/app/dashboard/vendors/page.js`:**
  - Clicking a vendor row or the **Details** action opens `VendorDetailModal`.
  - Shows store name, Approved/Pending badge, registration date, active products, lifetime sales (PKR), GPS status and coordinates with an OpenStreetMap link, owner name, CNIC, email and phone.
  - **Trust signals (last 30 days):** online orders the store cancelled to sell reserved units at the counter, and counter pickups locked by wrong codes (highlighted when above zero).
  - 1-click **Approve Store** / **Disapprove Store**; **View Store Products** opens the products page already filtered to that store (`/dashboard/products?store=…`).

### 2.2 Point 2: Saved Locations Proximity, Store Pins & Self-Pickup
* **Issue Addressed:** The customer default pin was Islamabad (`33.6844, 73.0479`) while the demo stores are in Karachi (`24.8556, 67.0224`) and Lahore (`31.5129, 74.3512`), which blocked delivery during testing ("too far"). Map tiles showed CARTO's "API KEY REQUIRED" image.
* **CARTO basemap (`core/widgets/map_tiles.dart`, identical in all 3 apps):**
  - The API key `cb1_5bea_1_834da8b386e3c4f989f8feca` lives in this one file; CARTO returns the "API key required" tile without it.
  - Light mode uses the Voyager style and dark mode the Dark Matter style.
  - Used by every map: the map picker (all apps), customer order tracking and the rider's active delivery.
* **Default customer location (`frontend-customer/lib/core/services/customer_location_storage.dart`):** `24.8620, 67.0300`, "Saddar, Karachi (Near Store)" — about 1.0 km from Karachi Electronics Hub, so home delivery works on first launch.
* **Location picker (`customer_home_screen.dart`):**
  - Every store from `GET /api/stores` is drawn as a store pin, so the customer can see where they can order from.
  - **Development builds only** (`APP_MODE=development`): demo presets *Saddar, Karachi*, *Gulberg, Lahore*, *Blue Area, Islamabad* and *COMSATS, Wah Cantt*. Each label shows the live distance to the nearest store that delivers there (e.g. "Saddar, Karachi · 1.0 km to Karachi Electronics Hub").
* **Cart (`cart_screen.dart`):** when the store is beyond the maximum delivery distance, the cart switches to self pickup and explains why. In development builds a **"Demo: set drop-off pin about 1 km from this store"** button moves the pin and re-enables home delivery (the snack bar shows the real distance).
* **Self-pickup flow:**
  - Every order gets a 4-digit handover code at checkout, visible only to the customer ("Show this code at the counter").
  - The tracking screen shows the store pin and a **Directions to the store** button that opens Google Maps (`core/services/maps_launcher.dart`).
  - The vendor marks the order collected with `PUT /api/vendor/orders/:id/deliver { otp }`; without the right code the handover is refused.

### 2.3 Point 3: Category Chips Design Revamp & App Performance
* **Issue Addressed:** The painted category motifs (circuit lines, wheat stalks, scissors) looked cluttered.
* **Squircle category tiles (`frontend-customer/lib/core/widgets/custom_category_chip.dart`):**
  - Removed `_MotifPainter`. Each tile is a rounded square with a soft tint of the category colour. The selected tile fills with the colour and gets a subtle shadow, and dark mode uses deeper tints.
  - Icons:
    - *All Products:* `Icons.dashboard_rounded` (Vendra Brand Orange)
    - *Electronics:* `Icons.devices_rounded`
    - *Mobile Accessories:* `Icons.headphones_rounded`
    - *Fashion:* `Icons.checkroom_rounded`
    - *Grocery:* `Icons.local_grocery_store_rounded`
    - *Home & Kitchen:* `Icons.restaurant_rounded`
    - *Health & Beauty:* `Icons.medical_services_rounded`
    - *Books & Stationery:* `Icons.menu_book_rounded`
* **Performance:**
  - Flutter Web in debug mode (`flutter run`) is JIT-compiled and noticeably slower. A release build (`--release`, optionally `--wasm`) gives smooth 60 FPS and above, up to the display's refresh rate.
  - Note: `--web-renderer` was removed in Flutter 3.29 and is not accepted by the installed Flutter 3.47. CanvasKit is already the default renderer.
  - Next.js `next dev` compiles pages on demand. `npm run build && npm start` serves pre-built pages.

### 2.4 Point 4: Anti-Abuse & Anti-Fraud Architecture
Vendra enforces 6 anti-abuse gates on the server; each is covered by `backend/tests/anti-abuse.test.js`:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       VENDRA ANTI-ABUSE GATES                               │
├───────────────────────┬─────────────────────────────────────────────────────┤
│ 1. False Dispute Trap │ A dispute FREEZES escrow; no auto-refund. Admin     │
│    (Customer Abuse)   │ reviews the dossier: handover proof + track records.│
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 2. Phantom Delivery   │ Rider cannot complete delivery without the 4-digit  │
│    (Rider Abuse)      │ code shown only on the customer's tracking screen.  │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 3. GPS Geofence Guard │ Delivery is refused if the rider is farther than    │
│    (Rider Abuse)      │ geofence_m (policy, default 200 m) from the pin.    │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 4. Double-Selling POS │ POS refuses units reserved by online orders; amber  │
│    (Vendor Abuse)     │ conflict modal; an override is audited.             │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 5. Counter Pickup OTP │ Self pickup is handed over only with the customer's │
│    (Customer/Vendor)  │ code; 5 wrong codes lock it for 10 minutes.         │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 6. Task Hoarding Guard│ A rider who accepts but doesn't reach the store in  │
│    (Rider Inactivity) │ rider_pickup_timeout_min loses it; back to the pool.│
└───────────────────────┴─────────────────────────────────────────────────────┘
```

**Audit trail (migration `015_abuse_guards.sql`, `services/trust.service.js`).** Each abuse signal is recorded in `trust_events` and counted against whoever caused it:

| Event | Recorded when | Counted against | Admin sees it on |
|---|---|---|---|
| `walk_in_override` | a cashier overrides a reservation and the online order is cancelled | the store (and the cashier's account) | Vendor details modal, dispute track records |
| `rider_task_timeout` | the sweep takes an accepted delivery back from a rider | the rider | Riders table flag, dispute track records |
| `handover_lockout` | 5 wrong handover codes lock an order | the rider (delivery) or the store counter (self pickup) | Riders table flag, Vendor details modal |

**Task hoarding (gate 6) in detail (`services/orderTimeouts.service.js` → `releaseIdleRiders`, every 30 s):**
* **What counts as hoarding:** a delivery still `ready_for_pickup`, with a rider assigned, no "arrived at store", and `assigned_at` older than `rider_pickup_timeout_min`. The admin can edit the policy (default 20 min; capped at 10 min in development mode).
* **When the deadline passes:**
  - The rider is removed and marked available again.
  - The released rider is told why; the customer and the store are told a new rider is being found.
  - The task is offered again to nearby online riders, except the one who let it lapse.
* **After the release:**
  - The lapsed rider can't re-accept it (`409 TASK_LAPSED`), and it is hidden from their task list.
  - `rider_released_at` restarts the "no rider found" clock, so the order is not auto-cancelled straight away.
* **Not hoarding:** a rider who has already arrived and is waiting at the store keeps the order.
* **Rider app:** while heading to the store, a live card shows "Reach the store by 2:40 PM · mm:ss left".

---

## 3. Anti-Abuse Matrix: Deep-Dive Verification

### 3.1 Scenario 1: Customer attempts to claim refund after receiving goods
* **Vulnerability:** Customer receives the package, then immediately opens a dispute claiming "Item never received" to get free merchandise.
* **Vendra Safeguard:**
  1. The handover requires the customer to give the rider the 4-digit code; the rider submits it with their GPS fix to `POST /api/rider/orders/:id/deliver { lat, lng, otp }`.
  2. On a match the order records `otp_verified_at`, `delivered_at` and the handover position (`delivery_lat/lng`), and the rider's GPS trail is kept until escrow settles.
  3. A dispute (`POST /api/disputes`) freezes escrow (`escrow_status: 'disputed'`). Nothing is refunded automatically, and the dispute-window release sweep skips frozen escrow.
  4. The admin's **forensic dossier** (`GET /api/admin/disputes/:id/dossier`) shows:
     - the code verification time
     - the handover position and its distance from the pin
     - the GPS trail and packing record
     - **track records** (the customer's earlier claims and how many were rejected, the store's walk-in overrides, the rider's lapsed tasks and lockouts)
  5. The admin dismisses the false claim (`resolution: 'release'`). The store is paid, and the customer's "claims rejected" count goes up for any future dispute.

### 3.2 Scenario 2: Rider attempts to mark order delivered while away from customer
* **Vulnerability:** Rider marks the order as delivered from home without visiting the customer.
* **Vendra Safeguard:**
  1. The rider app sends a fresh GPS fix with the delivery confirmation.
  2. The backend calculates the Haversine distance between the rider and the customer's pin:
     $$\text{distance} = 2 R \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta\phi}{2}\right) + \cos\phi_1 \cos\phi_2 \sin^2\left(\frac{\Delta\lambda}{2}\right)}\right)$$
  3. If $\text{distance} > \text{geofence\_m}$ (admin policy, default 200 m), the API returns `422` with `code: 'OUTSIDE_GEOFENCE'`, `distanceMeters` and `geofenceMeters`. The geofence is checked before the code, so a spoofed position alone can't finish a delivery.
  4. The same applies at the store: "arrived" and "picked up" need the rider within `pickup_geofence_m` of the store (`OUTSIDE_PICKUP_GEOFENCE`).

### 3.3 Scenario 3: Vendor attempts to sell reserved stock to walk-in customer
* **Vulnerability:** A customer places an online order for the last unit. A walk-in customer offers cash at the counter, and the cashier rings it up on the POS.
* **Vendra Safeguard:**
  1. Placing an online order locks its units (`inventory_locks`, `products.reserved_quantity`). The counter can sell only `private_stock − reserved_quantity`.
  2. When the cashier adds more than that, the POS shows the **amber conflict modal**. It lists the online orders holding the units (`GET /api/vendor/products/:id/reservations`), e.g. *"Item reserved for Online Order #VDR-00006"*, together with the shelf / buffer / reserved / online stock matrix.
  3. Without an override the sale is refused: `POST /api/vendor/pos/sales` → `409`, `code: 'RESERVED_STOCK'`.
  4. **Override & cancel online order** is explicit, and only for orders not yet packed. It:
     - cancels the newest such order
     - refunds the customer in full and notifies them
     - records a `walk_in_override` trust event (the penalty audit), which the admin sees on the store
   
   Packed orders can't be overridden.

---

## 4. Prompts for Future Execution & Additional Work

### Prompt A: Run Full High-Performance Production Build
```text
Please build and start the entire Vendra stack in optimized mode:
1. Build the Next.js admin panel for production:
   cd d:\FYP\frontend-admin
   npm run build
   npm start -- -p 3001
2. Launch the Flutter web apps as release builds (CanvasKit is the default renderer;
   --web-renderer no longer exists in Flutter 3.29+):
   cd d:\FYP\frontend-customer; flutter run -d chrome --release --web-port 5001
   cd d:\FYP\frontend-vendor; flutter run -d chrome --release --web-port 5002
   cd d:\FYP\frontend-rider; flutter run -d chrome --release --web-port 5003
   (add --wasm to try the WebAssembly build)
3. Verify that all 3 apps and the admin panel start with zero warnings.
```

### Prompt B: Automated End-to-End Anti-Abuse Test Suite — DONE
Implemented as `backend/tests/anti-abuse.test.js` (Node's built-in test runner, like the rest of the suite). It runs against a throwaway database:
```text
cd d:\FYP\backend
$env:TEST_DATABASE_URL = "postgresql://postgres:<password>@localhost:5433/vendra_it"
npm test
```
It asserts, with the API's real codes:
1. A dispute sets escrow to `disputed`, refunds nothing, and survives the release sweep. The dossier holds the handover proof and the track records, and dismissing the claim pays the store.
2. A wrong code returns `422 WRONG_OTP`, five wrong codes return `429 OTP_LOCKED`, and the lockout counts against the rider.
3. Delivering away from the pin returns `422 OUTSIDE_GEOFENCE`.
4. Selling reserved units returns `409 RESERVED_STOCK`, and an override records a `walk_in_override`.
5. A self-pickup handover needs the customer's code (`OTP_REQUIRED` / `WRONG_OTP`).
6. A rider who never reaches the store loses the task:
   - the task returns to the pool and is not cancelled
   - the rider can't re-accept it (`409 TASK_LAPSED`)
   - another rider can accept it
   - a rider waiting at the store keeps theirs

### Prompt C: FYP Mobile Screenshot Capture Tool
```text
Please run a Node.js Puppeteer script to capture mobile-dimension (390x844 iPhone 14 / Android viewport) high-resolution screenshots of:
1. Customer Home Screen with the squircle categories and the Saddar, Karachi delivery pin.
2. Customer Cart Screen showing the escrow protection badge (and, in development mode, the "pin near this store" button).
3. Customer Order Tracking Screen showing the 4-digit pickup code, the CARTO map and "Directions to the store".
4. Vendor POS Screen showing live inventory and the reservation conflict modal.
5. Rider Active Delivery Screen showing the road route, the geofence circle and the pickup deadline card.
6. Admin Dashboard in Light Mode and Dark Mode showing the Vendor Details modal with trust signals.
Save all screenshots with clean filenames in `d:\FYP\docs\screenshots\` for the final FYP report.
```

---

## 5. Verification Checklist

- [x] CARTO basemap key configured once (`map_tiles.dart`) and used by every map; dark tiles in dark mode.
- [x] Admin Panel dark mode CSS variable overrides compiled.
- [x] Admin Vendor Details modal implemented, with trust signals and a store-filtered products link.
- [x] Customer default location preset to Saddar, Karachi (~1.0 km from the store).
- [x] Every store pinned on the location picker; demo presets and pin shortcut limited to development builds.
- [x] Self-pickup counter code enforced by the API; directions to the store from the tracking screen.
- [x] Category icons redesigned into squircle tiles.
- [x] All 6 anti-abuse gates enforced in the backend and audited in `trust_events`.
- [x] `backend/tests/anti-abuse.test.js` passes (11 tests); full backend suite 167/167 (with the privacy tests from [VENDRA_SECURITY_AUDIT_UIUX_ENHANCEMENTS.md](VENDRA_SECURITY_AUDIT_UIUX_ENHANCEMENTS.md)).
- [x] `dart analyze` reports no issues in all 3 apps; their Flutter test suites pass.
- [x] Admin ESLint passes with 0 errors; `next build` succeeds.
