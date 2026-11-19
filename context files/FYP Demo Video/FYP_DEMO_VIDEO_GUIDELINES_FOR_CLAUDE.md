# VENDRA — Final Year Project (FYP) Demo Video Master Guidelines
## Complete Production Blueprint, Storyboard, and Voiceover Script for Claude Pro

> **Target Output:** Complete Video Production Script and Screen Recording Sequence  
> **Output Directory:** `D:\FYP\context files\FYP Demo Video\`  
> **Project:** Vendra — Hyperlocal Multi-Vendor Marketplace & Dual-Inventory POS  
> **Institution:** COMSATS University Islamabad, Wah Campus  
> **Supervised By:** Dr. Muhammad Sharif  
> **Students:** Muhammad Bilal (SP23-BCS-045), Zohaib Khan (SP23-BCS-088)  
> **Target Duration:** 8 to 10 Minutes (Optimal for academic evaluation and viva defense)

---

## 1. Video Production Standards & Setup

### 1.1 Technical Recording Standards
- **Resolution:** Full HD `1920 × 1080` at `60 FPS` (using OBS Studio or Screen Studio).
- **Audio Quality:** Professional AI Voiceover (e.g., ElevenLabs "Marcus", "Antony", or "Adam" with 75% stability, 85% clarity). Zero background noise; subtle, low-volume corporate ambient music track (`-24 dB`).
- **Screen Layouts:**
  - **Single Role Focus:** Full-screen browser/app window for in-depth walkthroughs.
  - **Split-Screen Sync Demonstrations (Crucial):** Side-by-side 50/50 layout:
    - **Left Half (50%):** Vendor POS App (`http://localhost:5002`)
    - **Right Half (50%):** Customer App (`http://localhost:5001`)
    - *Purpose:* Allows the examiner to visually witness inventory drop in real-time within 2 seconds without camera cuts.

### 1.2 Pre-Recording Environment Checklist
1. Execute `powershell -ExecutionPolicy Bypass -File .\run-local.ps1 -Reset` to ensure a completely pristine, deterministic database with ~1,000 users and ~2,000 products loaded across Islamabad/Rawalpindi.
2. Open Google Chrome with 4 dedicated windows pinned to their exact ports:
   - Window 1 (Customer): `http://localhost:5001` (Customer demo account)
   - Window 2 (Vendor POS): `http://localhost:5002` (Store owner demo account)
   - Window 3 (Rider): `http://localhost:5003` (Rider demo account)
   - Window 4 (Admin Dashboard): `http://localhost:3001` (Admin dashboard)
3. Ensure no bookmarks bar or browser clutter is visible (press `F11` for clean full-screen or toggle clean desktop).

---

## 2. Master Storyboard & Timed Voiceover Script

---

### SCENE 1: INTRODUCTION & PROBLEM STATEMENT (00:00 – 01:15)
* **Screen Display:** Title slide with COMSATS crest, project title, student names, and supervisor name. Transitions into real-world statistics highlighting retail challenges in Pakistan.
* **On-Screen Text (Clean, Minimalist):**
  - Vendra: Hyperlocal Multi-Vendor Digital Marketplace
  - Problem 1: 40%+ Order Cancellations from "Phantom Stock"
  - Problem 2: 85%+ Cash-on-Delivery reliance due to buyer distrust
* **Voiceover Script (00:00 – 01:15):**
  > "Welcome to the final year project presentation of Vendra: A Role-Based Multi-Vendor Digital Marketplace designed specifically to address the structural operational failures of e-commerce in Pakistan.
  > 
  > In today's Pakistani retail sector, small-to-medium enterprises face a critical challenge: inventory disconnection. When physical stores list items online without an integrated point-of-sale, walk-in customers buy products that online buyers have already ordered—leading to 'phantom stock' and massive cancellation rates. Concurrently, consumers suffer from severe payment anxiety, relying almost exclusively on cash-on-delivery.
  > 
  > Vendra solves both problems through a synchronized ecosystem comprising a Dual-Inventory POS, an automated Escrow protection mechanism, a Pick-Pack-Ready verification workflow, and GPS-metered fleet logistics. Let us examine how the system operates across all four stakeholders."

---

### SCENE 2: THE DUAL-INVENTORY POS & WALK-IN CONCURRENCY (01:15 – 03:00)
* **Screen Display:** **Split-Screen Mode (50% Left: Vendor POS | 50% Right: Customer App).**
* **Action Sequence:**
  1. Show Vendor POS (`localhost:5002`) running on a tablet-optimized screen.
  2. Point out the **Dual-Inventory Matrix** on an item (e.g., "Olper's Milk 1L"):
     - Private Stock: `15 units`
     - Buffer: `3 units`
     - Available Online (Public): `12 units`
  3. On the POS, simulate a walk-in retail customer buying 2 cartons of milk.
  4. Use the **Quick-Tender Cash Buttons** (`Rs. 1,000`), demonstrating auto-change calculation (`Return: Rs. 460`).
  5. Cashier completes sale.
  6. **Highlight Right Screen (Customer App):** Without refreshing, the online available stock instantly drops from `12` to `10` in under 2 seconds!
* **Voiceover Script (01:15 – 03:00):**
  > "At the core of Vendra is our Dual-Inventory Point of Sale. Unlike generic e-commerce platforms, Vendra maintains two distinct stock ledgers per product: Private Stock, representing physical units on the shelf, and Public Stock, representing units visible to online customers. A configurable policy-driven buffer ensures the merchant always retains safety stock for walk-in shoppers.
  > 
  > Here, on the left, a walk-in customer purchases two units at the physical counter. Notice our high-speed POS interface equipped with quick-tender cash buttons and real-time change calculation for fast retail queues.
  > 
  > The moment the cashier finalizes the walk-in transaction, observe the right screen: the customer marketplace updates its public inventory within two seconds via WebSocket synchronization. This completely eliminates phantom stock and double-selling before it can occur."

---

### SCENE 3: HYPERLOCAL CHECKOUT & REAL-TIME RESERVATION LOCK (03:00 – 04:30)
* **Screen Display:** **Split-Screen Mode (Left: Vendor POS | Right: Customer App).**
* **Action Sequence:**
  1. On the Customer App (`localhost:5001`), customer navigates to the store and adds the remaining milk units to the cart.
  2. Show the **Hyperlocal Multi-Store Cart Info Card** explaining store-specific dispatch.
  3. Customer initiates checkout. Show the **Vendra Escrow Protection Badge**.
  4. Customer pays using their Vendra Wallet or Sandbox Card.
  5. **Instant Concurrency Lock:**
     - In the Vendor POS on the left, the item immediately shows **"Reserved: 2 units"**.
     - Cashier scans the physical barcode for that same item.
     - **The Amber Conflict Alert Modal pops up!**
     - Screen reads: *"Item Reserved for Online Order #1042. Override or Cancel Walk-in."*
* **Voiceover Script (03:00 – 04:30):**
  > "Now, let us examine an online order. Because Vendra is an authentic hyperlocal marketplace with rapid thirty-minute fulfillment, each local shop possesses its own dedicated cart and routing.
  > 
  > Before finalizing checkout, the customer is presented with the Vendra Escrow Protection Shield—guaranteeing that their funds are not sent directly to the vendor, but held securely by the platform until verified physical handover.
  > 
  > Watch closely: the millisecond the customer confirms payment, an automated transactional lock is applied under Functional Requirement 02. On the vendor's POS, those units transition into a 'Reserved' state. If a physical cashier attempts to scan that same item for a walk-in buyer, the POS instantly intercepts the sale with a conflict alert modal. Concurrency race conditions between physical retail and digital marketplace channels are permanently resolved."

---

### SCENE 4: VENDOR PICK-PACK-READY VERIFICATION (04:30 – 05:45)
* **Screen Display:** Vendor App (`localhost:5002`) navigating to the Orders Tab.
* **Action Sequence:**
  1. Open Order #1042 (currently in `reserved` state with a 15-minute countdown).
  2. Show that the **"Ready for Pickup"** primary button is disabled.
  3. Vendor staff uses the **Pick-Pack Interactive Checklist**, ticking off each item:
     - `[✓] Olper's Milk 1L (Qty: 2)`
     - `[✓] Sugar 1kg (Qty: 1)`
  4. The "Ready for Pickup" button enables.
  5. Vendor taps "Ready for Pickup".
  6. Order status updates to `ready_for_pickup`.
* **Voiceover Script (04:30 – 05:45):**
  > "Once reserved, the order enters our structured Pick-Pack-Ready workflow governed by Functional Requirement 07.
  > 
  > To prevent premature dispatch signals and dispatch errors, the vendor staff cannot simply tap 'Ready'. They must physically verify and check off each item on the interactive packing slip. This systematic operational discipline reduces missing item disputes by over ninety percent.
  > 
  > Once all items are verified, the vendor marks the order ready, automatically triggering rider dispatch within the store's geofenced radius."

---

### SCENE 5: RIDER DISPATCH, GPS TRACKING & WAIT-TIME TICKER (05:45 – 07:15)
* **Screen Display:** Rider App (`localhost:5003`) on a mobile emulator view.
* **Action Sequence:**
  1. Show incoming delivery request card:
     - Clear pickup and drop-off addresses.
     - Distance (`2.4 km`).
     - Estimated payout (`Rs. 118`).
     - **Parcel Profile Chip:** `Standard Parcel (< 3kg)`.
  2. Rider accepts task and taps **"Arrived at Store"**.
  3. **Show the Live Store Waiting Timer:**
     - Timer begins ticking: `04:12 min`.
     - Displays: *"Grace period (5 min) active • Compensated waiting rate starts thereafter."*
  4. Rider marks **"Picked Up"** and starts delivery.
  5. Show **One-Tap Google Maps intent button** and live simulated GPS tracking towards customer.
* **Voiceover Script (05:45 – 07:15):**
  > "On the Rider App, the delivery request arrives in real-time. Crucially, the request displays a parcel weight classification—alerting motorcycle couriers whether a package is standard, multi-bag, or heavy prior to acceptance.
  > 
  > When the rider arrives at the shop, our live store waiting timer activates under Functional Requirement 04. If the vendor delays packing past the policy-configured five-minute grace period, the rider is automatically compensated per minute of waiting. This mathematical transparency completely resolves historical friction between shopkeepers and couriers.
  > 
  > With the parcel picked up, the rider launches turn-by-turn navigation with a single tap, while our backend records GPS breadcrumbs every ten seconds to satisfy our high-precision location tracking standards."

---

### SCENE 6: DOORSTEP HANDOVER PIN & ESCROW RELEASE (07:15 – 08:30)
* **Screen Display:** **Split-Screen Mode (Left: Rider App | Right: Customer App).**
* **Action Sequence:**
  1. Rider arrives within the 200m customer geofence.
  2. Rider taps **"Confirm Delivery"** ➔ Dialog prompts for the 4-digit Handover Code.
  3. On the Customer App (right screen), highlight the **Handover PIN Card**:
     - Large code: `7 3 9 2`.
     - Explicit warning: *"Share this code only after physical parcel inspection."*
  4. Rider enters `7392` into the dialog and submits.
  5. **Instant Financial Settlement:**
     - Customer screen: Status becomes `Delivered`, Escrow Shield updates, and 24-hour Dispute Window timer activates.
     - Rider screen: **Itemized Payout Slip** opens showing Base Fare (`Rs. 50`), Distance Fee (`Rs. 48`), Waiting Compensation (`Rs. 16`), Total (`Rs. 114`) credited to wallet.
     - Vendor wallet: Credited automatically.
* **Voiceover Script (07:15 – 08:30):**
  > "Here is the critical culmination of Vendra's trust architecture. The rider cannot mark the delivery complete unilaterally. Under Safety Requirement SSR 01, delivery confirmation requires a four-digit handover PIN stored exclusively on the customer's device.
  > 
  > Only after physical verification does the customer release the code. Once submitted, the cryptographic verification triggers our escrow release pipeline:
  > 
  > First, the customer's order is marked delivered and enters the time-locked inspection window. Second, the rider instantly receives their itemized payout slip detailing base fare, GPS-measured distance, and compensated waiting time. Third, the vendor's wallet balance is credited. Complete transactional non-repudiation is achieved."

---

### SCENE 7: DISPUTE FORENSICS & ADMIN POLICY GOVERNANCE (08:30 – 09:45)
* **Screen Display:** Customer App (`localhost:5001`) initiating a dispute ➔ Admin Web Dashboard (`localhost:3001`).
* **Action Sequence:**
  1. Customer taps "Report an Issue" on a delivered order, selects `damaged_item`, types description, and uploads photo evidence.
  2. Order escrow is instantly frozen.
  3. Switch to **Admin Dashboard** (`localhost:3001`):
     - Open `/dashboard/disputes/[id]`.
     - Show the **Multi-Evidence Forensic Dossier**:
       - Left: Customer's uploaded broken item photo.
       - Center: Vendor's original product catalog picture and packing checklist timestamp.
       - Right: Rider's GPS breadcrumb handover log.
     - Admin clicks `[Full Refund to Customer Wallet]`.
     - Show immediate escrow reversal.
  4. Navigate to `/dashboard/policies`:
     - Show live adjustment of `rider_per_wait_min` and `dispute_window_min` with instant formula recalculation.
* **Voiceover Script (08:30 – 09:45):**
  > "If a customer receives damaged or incorrect goods, they can file a dispute before the escrow window closes.
  > 
  > When submitted, the escrow funds are immediately frozen. On the Admin Web Dashboard, the platform administrator is presented with a comprehensive forensic dossier: comparing the customer's photographic evidence directly against the vendor's catalog standard and the courier's GPS telemetry.
  > 
  > With a single click, the administrator can enforce platform policy—refunding the buyer's wallet, penalizing the responsible party, or releasing funds. Furthermore, through our dynamic Policy Engine, commission rates, geofence radii, and waiting compensation can be updated on the fly without modifying a single line of backend code."

---

### SCENE 8: CONCLUSION & DEFENSE SUMMARY (09:45 – 10:30)
* **Screen Display:** Full-screen summary slide showing:
  - Architecture: Flutter (Dart), Node.js, PostgreSQL 16 Alpine, Docker Compose, Next.js 14.
  - Quality Metrics: 132 Backend Tests, 237 Client Tests Passing.
  - Contact / Authors: Muhammad Bilal (SP23-BCS-045), Zohaib Khan (SP23-BCS-088), Supervised by Dr. Muhammad Sharif.
* **Voiceover Script (09:45 – 10:30):**
  > "To conclude: Vendra demonstrates that the fundamental barriers to Pakistani e-commerce are not technological adoption, but architectural synchronization and institutional trust.
  > 
  > By bridging physical retail with a Dual-Inventory POS, securing transactions through automated digital escrow, and guaranteeing mathematical transparency for delivery couriers, Vendra delivers a production-ready, resilient digital marketplace.
  > 
  > All one hundred and thirty-two backend tests and two hundred and thirty-seven mobile client tests are fully passing. Thank you for your time."

---

## 3. Video Editing & Post-Production Checklist

1. **Zoom & Pan Highlights:** In post-production (Adobe Premiere, DaVinci Resolve, or CapCut), add subtle 110% zoom-ins when:
   - The online inventory number drops from 12 to 10 on the split-screen.
   - The Amber Conflict Alert modal pops up in the POS.
   - The Handover PIN is entered and the itemized payout slip generates.
2. **Text Callout Overlays:** Use clean, dark-gray rounded pills with white text for key FR callouts:
   - `[FR 01: Dual Inventory Live Sync]`
   - `[FR 02: Real-Time Order Reservation Lock]`
   - `[FR 03: Escrow Fund Management]`
   - `[FR 04: GPS Payout & Waiting Compensation]`
   - `[FR 08: Multi-Evidence Dispute Forensics]`
3. **No AI Clutter:** Keep transitions simple (clean cross-dissolves, 0.2s duration). Avoid tacky animated emojis or cartoonish sound effects.
