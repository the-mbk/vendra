# Vendra Platform: UI/UX Assessment, Use Cases & Functional Roadmap

> **Project:** Vendra Multi-Vendor Digital Marketplace & Quick-Commerce System
> **Institution:** COMSATS University Islamabad, Wah Campus — Department of Computer Science
> **Purpose:** Proposed use cases, UI/UX patterns and operations features, with their implementation status checked against the code.
> **Updated:** November 18, 2026
> **Companion documents:**
> - [VENDRA_SYSTEM_IMPROVEMENTS_AND_ABUSE_PREVENTION.md](VENDRA_SYSTEM_IMPROVEMENTS_AND_ABUSE_PREVENTION.md)
> - [VENDRA_SECURITY_AUDIT_UIUX_ENHANCEMENTS.md](VENDRA_SECURITY_AUDIT_UIUX_ENHANCEMENTS.md)

---

## 1. Status at a Glance

| # | Proposal | Status | Where |
|---|---|---|---|
| 2.1 | Multi-store carts, sequential checkout | **Done** | Customer: *My carts*, plus the *Next cart* card after checkout |
| 2.2 | Delivery notes + in-app chat without phone numbers | **Done** | Checkout note; customer ↔ rider chat (`/api/orders/:id/messages`) |
| 2.3 | Scheduled delivery slots | **Not built** (see §8) | — |
| 3.1 | Camera barcode scanning with a beep | **Done** | Browser and phone camera; beep on read |
| 3.2 | 80 mm thermal receipt | **Done** (no GST line, see §8) | POS → receipt, print/share PDF |
| 3.3 | Low-stock / reserved badges on the POS | **Done** | POS product tiles |
| 4.1 | Voice cues for riders | **Done** (event cues, see §8) | Rider delivery screen, speaker toggle |
| 4.2 | Demand map for idle riders | **Done** | Rider home, *Where the work is* |
| 4.3 | Adaptive GPS sampling | **Done** (10 s / 30 s) | Rider location service |
| 5.1 | Live fleet map | **Done** | Admin → *Live Map* |
| 5.2 | Escrow batch settlement + countdown | **Done** | Admin → Finance → *Escrow settlement* |
| 5.3 | Admin audit trail | **Done** | Admin → Policies → *Admin audit trail* |
| 6.1 | Loading / empty / network / destructive states | **Done** | All apps and the admin panel |
| 6.2 | Slide to deliver; animated tracking stepper | **Done** | Rider handover; customer tracking |

---

## 2. Customer

### 2.1 Multi-store carts and sequential checkout
Each store sends its own rider, so an order comes from one store (SRDS §1.1, §2.2).

- **My carts:** lists every store's cart with its total and whether that store delivers to the customer's pin.
- **Next cart:** after an order is placed, the confirmation screen shows *Next cart: Lahore Fashion (1 item · Rs. 2,499)* with **Check out next cart**.
- **What carries over:** the delivery pin and address. Wallet payment needs no re-entry; a card is entered again at its own checkout.

### 2.2 Delivery notes and in-app chat
- **Note for the rider:** optional, up to 200 characters.
  - Quick chips: *Leave it at the door*, *Please don't ring the bell*, *Hand it to the guard*, *Call out at the gate*.
  - Shown only to the rider who accepts the order. It is hidden from the open task list, because it may contain a gate code.
- **Chat:** the customer and the assigned rider message each other inside the app (`GET/POST /api/orders/:id/messages`, live as `chat:message`).
  - No phone number changes hands.
  - Each side has one-tap quick replies.
  - Open only while a rider is on the delivery. After that the thread is read-only.
  - Messages are append-only and appear in the admin order drawer as dispute evidence.
  - A rider only sees messages from their own time on the order.

### 2.3 Delivery time slots
Not built; see §8.

---

## 3. Vendor POS and Inventory

### 3.1 Camera barcode scanning
- `mobile_scanner` reads barcodes from a laptop webcam (browser) or a phone camera. A typed fallback covers devices without a camera.
- **Feedback on every read:** a short beep in the browser (Web Audio), or a click and a vibration on a phone.
- **What a scan does depends on the screen:**
  - POS: adds the item (scanning again adds another unit).
  - Packing checklist: packs one unit.
  - Stock in: opens the product to receive stock.
  - Product form: fills in the barcode.
- A scanned item that is reserved for online orders opens the conflict modal.

### 3.2 Thermal receipt
After a POS sale the receipt is an 80 mm roll PDF (`PdfPageFormat.roll80`) to print or share. It contains:
- store header and address
- receipt number, date and cashier
- the lines and totals
- payment details and a QR code
- the store's custom footer (set in *Receipt settings*)

### 3.3 Stock warnings on POS tiles
Sellable at the counter means shelf minus units reserved for online orders.

| Situation | Tile shows |
|---|---|
| 1–2 sellable | Amber *Only 2 left for counter* |
| None sellable, but units on the shelf are all reserved online | Pulsing padlock *Reserved online* (ringing it up opens the conflict modal listing the orders, e.g. *Online Order #VDR-00006*) |
| Nothing on the shelf | *Sold out* |

---

## 4. Rider

### 4.1 Voice cues
Spoken with the browser's speech engine, once per delivery:

| When | The rider hears |
|---|---|
| Accepted | "New delivery. Head to Karachi Electronics Hub." |
| Within the geofence of the store | "You have arrived at …. Tap arrived at store." |
| Picked up | "Order picked up. Head to the customer." |
| Within the delivery geofence | "You are at the drop-off. Ask the customer for the four digit code." |
| Delivered | "Delivery complete." |

A speaker button in the delivery screen turns cues on or off, and the choice is remembered. Where the device has no speech engine, the button is hidden.

### 4.2 Demand map
An online rider with no requests sees a small map of nearby stores (within 25 km) that have delivery orders today (`GET /api/rider/demand`). Each store is coloured by how busy it is:

| Colour | Means |
|---|---|
| Red | 6+ orders in the last hour, or 2+ deliveries waiting for a rider |
| Amber | 2+ orders in the last hour, or 1 waiting |
| Green | Quiet |

The three busiest are listed under the map. The data is real order counts, with no customer data, refreshed every minute.

### 4.3 Adaptive location updates
- **On a delivery** (or a simulated drive): every **10 s**, as SRDS PR 03 requires, for payout distance and live tracking.
- **Online without a delivery:** every **30 s**, saving battery and data.
- **How it switches:** the server's reply to each location update says whether the rider is on a delivery, and the app switches rhythm. Accepting a task switches to 10 s at once.

The document originally proposed 2.5 s while moving. That isn't used, because it would multiply server writes with no gain over the 10 s the SRDS specifies.

---

## 5. Admin

### 5.1 Live fleet map
*Live Map* (`/dashboard/fleet-map`) polls `GET /api/admin/fleet` every 10 s and draws:
- **Riders:** online riders, green when on a delivery and blue when free.
- **Stores:** each store, with a pulsing badge counting orders waiting for a rider.
- **Routes:** every delivery in flight, *rider → store* (amber, dashed) before pickup and *rider → customer* (navy) after.
- **Side list:** the deliveries in flight. Clicking one zooms to its three points, and long store waits are flagged.

The map is a small built-in tile renderer (CARTO tiles, Web Mercator), with no map library added.

### 5.2 Escrow settlement
The background sweep already releases escrow every 30 s once an order's dispute window has passed.
- **What release means:** the store is paid its subtotal minus commission, and the platform ledger is written. Orders with an open dispute are never released.
- **Finance → Escrow settlement** shows:
  - what is due now
  - what falls due in the next 24 hours, and the next due time
  - a live countdown to the next automatic run
  - **Release due now**, with a confirmation step, which runs the same release at once and is recorded in the audit trail

The SQL in the original proposal only changed `escrow_status`, without paying the store or writing the ledger, so it was not used.

### 5.3 Admin audit trail
- **Table:** `admin_audit_log`, append-only and enforced by a database trigger.
- **One row per admin action,** written in the same transaction as the action:
  - store approval and disapproval, and store location reviews
  - product approve / hide
  - policy changes, recorded as old → new values
  - rider approve / reject, with the reason
  - dispute rulings, with the outcome and note
  - password resets (the temporary password is never logged)
  - manual escrow releases
- **Each row records** who, when, the IP address, a readable summary and details.
- **Where to see it:** *Policies* → *Admin audit trail*, filterable by action, with paging.

---

## 6. Cross-Platform States and Interactions

### 6.1 States
| State | Implementation |
|---|---|
| Loading | Shimmer skeletons in the apps; spinners only for small inline waits |
| Empty search | *No products match "x"*, with category chips to jump to and *Show everything* |
| Network drop | All three apps: a non-blocking amber pill *Connection dropped. Reconnecting…* with *Retry now*. It appears after 2 s offline and disappears when the live connection returns. |
| Destructive actions | Admin: *Disapprove store*, *Hide product*, *Release due now* and the dispute rulings need a second, explicit confirmation stating the consequence. Customer *Cancel order* and the vendor's POS override show the amounts or orders affected before confirming. |

### 6.2 Interactions
1. **Slide to confirm delivery** (rider): the final handover is a slide, so a phone in a pocket can't confirm it. Releasing early springs back. Screen readers get a normal activate action.
2. **Tracking stepper** (customer):
   - every step has an icon, and the current one pulses
   - steps: placed, confirmed, packed, rider assigned, picked up, on the way, **at your door**, delivered
   - *At your door* lights up when the rider's live position is inside the delivery geofence

---

## 7. Viva Demonstration Script

| Act | What to show |
|---|---|
| 1. Anti double-selling | The customer orders the last unit. On the POS that tile turns into a pulsing *Reserved online*, and ringing it up opens the conflict modal naming the order. |
| 2. Location and escrow | The customer sets a pin near the store and adds a note for the rider. Checkout shows the escrow badge, and the money waits in the escrow pool. |
| 3. Store fulfilment | The vendor accepts, scans the items on the packing checklist (beep per scan), and marks the order ready. *Stock in* by scan shows the ledger entry. |
| 4. Rider and handover | The rider accepts (voice: "Head to …") and messages the customer. A simulated drive follows real roads, watched on the admin *Live Map*. Delivering outside the 200 m geofence is refused. Inside it, the customer's stepper shows *At your door*, the rider asks for the code and slides to confirm. |
| 5. Admin oversight | The order drawer shows the code time, the distance from the pin, the chat and the money split. In Finance: escrow settlement and reconciliation. In Policies: the audit trail, showing who changed what. |

---

## 8. Not Built, and Why

| Proposal | Decision |
|---|---|
| **2.3 Scheduled delivery slots** | Left out. Vendra is quick commerce: checkout reserves stock and holds escrow under timeouts (`vendor_accept_timeout_min`, `rider_assign_timeout_min`) that cancel and refund stalled orders. A slot hours away would lock reserved units away from walk-in customers for that long (SRDS FR 02, SSR 04) and needs a separate dispatch scheduler. It is a deliberate scope decision. |
| **Turn-by-turn voice** ("Turn right in 150 m") | Needs routing instructions per manoeuvre. The app has the road geometry from OSRM but not spoken steps; riders use Google Maps navigation for that (*Navigate* button, two-wheeler mode). Vendra speaks the delivery's own events (§4.1). |
| **Voice cues on Android builds** | They use the browser's speech engine. The apps run as Flutter web; a native Android build would need a text-to-speech plugin, which can be added later. |
| **GST line on receipts** | Vendra has no tax settings or tax-inclusive prices, so the figure would be invented. Add it when a tax rate becomes a policy. |
| **Saved card for the next cart** | Wallet checkouts need nothing re-entered. Saving cards means storing payment methods with the gateway, which is outside the current scope. |
| **Confetti on delivery** | Replaced by the completed stepper and the payout summary; a celebration animation adds nothing to the task. |

---

## 9. Verification

- **Backend:** 176 / 176 tests pass on a throwaway database. `roadmap-features.test.js` covers notes, chat access and closing, the demand map, fleet positions, settlement and the audit trail.
- **Flutter:** `dart analyze` reports no issues in customer, vendor and rider. The new unit tests cover voice cues, the GPS rhythm, rider note chips, the *At your door* rule and the POS badges.
- **Admin panel:** ESLint shows 0 errors and `next build` succeeds.
