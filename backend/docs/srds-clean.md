# Software Requirements Specification & Design Description

## Vendra: A Multi-Vendor Digital Marketplace for Global Commerce

| Name | Registration Number |
|---|---|
| Muhammad Bilal | SP23-BCS-045 |
| Zohaib Khan | SP23-BCS-088 |

**Supervised By:** Dr. Muhammad Sharif
**COMSATS University of Information Technology, Wah Campus**

> Reconstructed from a garbled PDF→Markdown/text conversion (`SRDS Vendra LATEST.pdf` / `SRDS Vendra LATEST.md` / `srds.txt`). Content is preserved in full; only formatting (headings, tables, lists, stray page numbers/headers/footers, OCR noise) has been repaired. Diagram *images* could not be recovered from the OCR text — where a figure appeared, its meaning has been reconstructed as prose/pseudo-code/lists from the surrounding (non-garbled) explanatory text, and is marked accordingly.

---

## Abbreviations

| Term | Meaning |
|---|---|
| API | Application Programming Interface |
| ERD | Entity Relationship Diagram |
| FR | Functional Requirement |
| GPS | Global Positioning System |
| JWT | JSON Web Tokens |
| POS | Point of Sale |
| RBAC | Role-Based Access Control |
| SDA | Software Design and Architecture |
| SME | Small-to-Medium Enterprise |
| SSR | Safety and Security Requirement |
| UML | Unified Modeling Language |

---

## 1. Introduction

### 1.1 System Introduction

Vendra is a role-based, multi-vendor e-commerce and delivery platform that aims to address the structural operational challenges of the digital marketplace in Pakistan. The system acts as a central point where customers, vendors, riders, and an organization/admin can securely access the system based on their roles. The main innovation is the combination of a Vendor POS which handles "Dual Inventory" (private actual stock for the physical store, and public visible stock for online customers).

### 1.2 Background of the System

In today's Pakistani market, online platforms such as Daraz or Foodpanda often experience "order failures" when vendors do not keep inventory updated in real-time across both the online platform and the physical store. There are no affordable, integrated tools for vendors to handle walk-in sales and digital orders simultaneously. Vendra's solution is a single POS that streamlines inventory management and introduces an escrow system to build trust between buyer and seller.

### 1.3 Objectives of the System

The main objective of Vendra is to establish a harmonized, trusted digital marketplace via the following specific objectives:

- **Reduction of Order Cancellations and Failures** — Overcome the "phantom stock" issue (physical shop stock shown as available online when it isn't) by integrating a real-time Vendor POS, so customers only see and order what is actually in the store.
- **Digitization of SME Vendors** — Offer small-to-medium enterprises a low-cost, web-based point-of-sale solution to manage inventory, pricing, and staff roles (cashier, packer, inventory manager) without costly third-party software.
- **Implementation of a Trust-Based Payment Ecosystem** — Establish an escrow mechanism where the platform holds customer payments and releases them to vendors only after successful delivery or dispute resolution, reducing fraud and boosting buyer trust.
- **Optimization of Delivery Operations** — Create a structured own-fleet rider management system that tracks delivery state (picked, on the way, delivered) and ensures fair rider compensation via a formula accounting for base fees, distance traveled, and waiting time.
- **Enabling Policy-Driven Governance** — Remove hard-coded business logic in favor of a configurable Policy Engine, letting Admins create/modify cancellation, penalty, service, and dispute-resolution rules dynamically.
- **Structural Inventory Accuracy (Dual Inventory)** — Maintain both Private Stock (actual physical count) and Public Stock (visible online quantity) so vendors can keep a safety margin for walk-in customers while serving online customers.
- **Role-Based Accountability** — Provide secure, distinct workflows for each actor (Admin, Vendor, Rider, Customer) backed by strong RBAC.

### 1.4 Significance of the System

The system digitizes small vendors — giving them a "shop brain" that prevents over-selling — at no licensing cost. It provides a safe purchasing environment for customers by securing their payments, and a clear, transparent payout structure for riders.

---

## 2. Overall Description

### 2.1 Product Perspective

Vendra is an all-new digital ecosystem built specifically for a mobile-first retail environment. It is not a replacement for an existing product but a contemporary solution for SMEs struggling with manual, disconnected sales processes across physical and digital channels. The product responds to Pakistan's "phantom stock" problem — where a shop's physical stock and its online store are out of sync, causing frequent order cancellations. Vendra acts as the "brain of the shop," connecting walk-in and digital marketplace activity through a centralized operation on a specialized Android-based POS.

*(Figure 2.1 — System Context Diagram, reconstructed: a central "Vendra Digital Marketplace" cloud/web environment exposes a Customer Module, a POS & Inventory Subsystem, a Mobile Tracking system, an Escrow & Payment module, a Policy & Dispute Engine, a Notification Module, and a Rider Module, all sitting behind an Authentication & RBAC layer and an Admin Dashboard.)*

### 2.2 Product Scope

Vendra's scope centers on a high-integrity, mobile-first operational backbone for multi-vendor commerce, optimized exclusively for the **Android platform**. The software manages the end-to-end lifecycle of a transaction — from the moment a vendor scans a physical item into inventory via smartphone, to a rider confirming delivery and funds being released from escrow. By targeting the "broken backbone" of current marketplaces, the system primarily addresses inventory synchronization and trust-building through a unified mobile infrastructure.

### 2.3 Product Functionality

The platform bridges physical retail with digital commerce, via **mobile devices** for primary users and a **web interface** for administrative oversight. Major functions, organized by primary user role:

**Core Administrative & Security Functions**
- **Authentication & Role-Based Access (RBAC)** — Securely authenticates all users via JWT sessions, granting role-specific permissions to Admins, Vendors, Riders, and Customers.
- **Policy & Governance Engine** — Lets the Admin configure platform-wide rules (commission fees, service charges, cancellation penalties, refund logic) via a web dashboard.
- **Dispute & Resolution Management** — A structured workflow for resolving conflicts using photo evidence and timestamps uploaded through mobile apps.

**Vendor & Inventory Functions (Mobile Interface)**
- **Dual Inventory POS Operations** — Vendors perform walk-in sales and manage stock via a mobile interface tracking both Private Stock (actual physical count) and Public Stock (customer-visible quantity).
- **Automated Order Reservation** — Instantly "locks" inventory items in the POS when an online order is placed, preventing accidental double-selling to walk-in customers.
- **Pick-Pack-Ready Workflow** — Guides vendor staff through picking and packing orders, updating status to "Ready for Pickup" to trigger rider assignment.
- **Real-Time Stock Ledger** — Maintains a digital history of all "Stock In" and "Stock Out" events for auditing and inventory accuracy.

**Customer Marketplace Functions (Mobile Interface)**
- **Digital Storefront Browsing** — View nearby stores, browse product catalogs, and check real-time availability based on vendor policy rules.
- **Secure Checkout & Escrow Payment** — Order placement where funds are held in escrow rather than paid directly to the vendor up front.
- **Order Tracking & Reviews** — Live order status updates plus post-delivery reviews/complaint submission.

**Rider & Delivery Functions (Mobile Interface)**
- **Task Assignment** — Real-time task notifications to riders based on availability and proximity to "Ready" orders.
- **Delivery State Management** — Riders update order progress (Picked, On the Way, Delivered) from their device.
- **GPS-Based Payout Tracking** — Automatically calculates rider earnings per task from a formula considering base fees, distance traveled, and waiting time.

### 2.4 Users and Characteristics

- **2.4.1 Vendors** — Shop owners with basic technical literacy who use the mobile interface for high-frequency tasks: barcode scanning, inventory management, digital order processing. They supply the real-time stock data required to prevent order failures.
- **2.4.2 Customers** — General mobile users who browse catalogs, place orders, and track deliveries occasionally or frequently. They rely on the escrow mechanism to keep payments secure until delivery is verified.
- **2.4.3 Riders** — High-mobility delivery personnel who accept tasks and update delivery state from their mobile devices, triggering fund release. Compensation is calculated transparently via a GPS-verified formula based on distance and waiting time.
- **2.4.4 Platform Administrators** — Technical managers who use a web dashboard to oversee governance, approve users, and configure policy rules. Secondary users who mainly intervene to resolve complex disputes using uploaded evidence.

### 2.5 Operating Environment

| Interface | OS / Environment | Language / Framework |
|---|---|---|
| Android | 5.0 and above | Java / React Native |
| Website | Modern Web Browser | React |
| Desktop (Admin) | — | — |

*Table 2.1 — Operating Environment*

> Note: the original document specifies **React Native** for Android and **React** for web as the intended frameworks. The current codebase instead uses **Flutter/Dart** for the mobile app(s) and **Next.js/React** for the admin web dashboard — Flutter satisfies the spirit of "cross-platform mobile," but this is a deviation from the literal spec worth flagging (see reorganization plan discrepancies).

#### 2.5.1 Android View

Designed as a high-performance, mobile-first interface for Riders and Customers on the go. Optimized for quick touch interactions, barcode scanning, and real-time GPS tracking.

Referenced mobile screens (from Stitch-generated mockups included in the repo under `context files/stitch_vendra_marketplace_ecosystem/`):
- *Figure 2.2 — Login Mobile*: role selector (Customer / Vendor / Rider) plus phone/email + password fields.
- *Figure 2.3 — Product Detail Mobile*: product view showing price, ratings, "sold by <vendor>", and an escrow-secured payment notice ("funds are held until you confirm delivery").
- *Figure 2.4 — Customer Homepage Mobile*: delivery address bar, search, category grid, nearby stores list, and a personalized product feed.
- *Figure 2.5 — Dispute Submission Mobile*: a 2-step "Report an Issue" flow (issue type selection → description + evidence attachment) with an escrow-held-funds reassurance banner.
- *Figure 2.6 — Order Tracking Mobile*: live order timeline (Confirmed → Prepared & Packed → Out for Delivery → Delivered) with escrow status and order summary.
- *Figure 2.7 — Rider Home Mobile*: rider earnings summary, online/offline toggle, and an incoming delivery request card (pickup/drop-off addresses, distance, estimated payout, accept/decline).

#### 2.5.2 Tablet View

Tailored for the **Vendor POS**, giving a larger workspace for inventory management: side-by-side active-orders and real-time stock views for faster in-store processing.

- *Figure 2.8 — POS Screen Tablet*: current-sale/checkout view with running total, intended for walk-in transactions.

#### 2.5.3 Web Browser View

A full-scale dashboard for the **System Admin** and deep data analysis: complex data visualization for the Policy Engine, user management, and financial auditing.

- *Figure 2.9 — Admin Dashboard Web*: platform KPIs (vendors, customers, daily orders & revenue, pending approvals), platform health, and a recent-disputes panel.
- *Figure 2.10 — Customer Homepage Web*: browser storefront ("Pakistan's Digital Bazaar") with category browsing and login/signup.
- *Figure 2.11 — Vendor Dashboard Web*: vendor-facing web view of revenue overview, live orders, quick actions, and restock alerts.

---

## 3. Specific Requirements

### 3.1 Functional Requirements

These define exactly what the system does: managing inventory synchronization between shop and marketplace, and the specific workflows for payment security and delivery accountability.

**FR 01 — Dual Inventory Synchronization**
| | |
|---|---|
| Actors | Vendor, System |
| Description | Maintains two concurrent stock values per product: Private (actual physical units) and Public (visible online quantity). |
| Preconditions | Vendor is registered and authenticated; product catalog is initialized in the database. |
| Basic flow | Vendor adds stock via mobile camera barcode scanning → System calculates Public Stock by subtracting a policy-driven buffer from Private Stock. |
| Risk | Network failure delays synchronization between shop and marketplace. |

**FR 02 — Real-time Order Reservation**
| | |
|---|---|
| Actors | Customer, Vendor, System |
| Description | Automatically "locks" inventory items in the vendor's POS when a customer places an online order. |
| Preconditions | Customer has items in the mobile cart and initiates checkout; items have sufficient Public Stock. |
| Basic flow | System creates a temporary reservation for the specific units → POS on the vendor's phone reflects "Reserved" status for walk-in cashiers. |
| Risk | Concurrent walk-in sale and online order at the exact same millisecond (race condition). |

**FR 03 — Escrow Fund Management**
| | |
|---|---|
| Actors | Customer, Rider, System |
| Description | Holds customer funds securely until delivery verification is completed by the rider. |
| Preconditions | Customer completes a successful digital payment transaction. |
| Basic flow | Funds move to a "Held in Escrow" state in the database → System releases funds to the vendor wallet only once the Rider marks "Delivered" on mobile. |
| Risk | A dishonest rider marking delivery without physical handover. |

**FR 04 — GPS-Based Rider Payout**
| | |
|---|---|
| Actors | Rider, System |
| Description | Calculates rider earnings based on verified distance and waiting-time rules. |
| Preconditions | Rider has GPS/location services active on their device. |
| Basic flow | System tracks GPS coordinates from pickup to delivery location. |
| Risk | GPS signal loss in high-density urban areas causing incorrect distance calculation. |

**FR 05 — Secure Role-Based Login**
| | |
|---|---|
| Actors | All Users |
| Description | Distinct, secure access for Admin, Vendor, Rider, and Customer roles via JWT sessions. |
| Preconditions | User has the mobile app or web dashboard access. |
| Basic flow | System validates credentials and grants access only to the user's assigned role-specific dashboard. |
| Risk | Unauthorized access if session tokens are compromised. |

**FR 06 — Product Catalog Management**
| | |
|---|---|
| Actors | Vendor, Admin |
| Description | Vendors add, update, and manage products, pricing, and categories on the platform. |
| Basic flow | Vendor inputs product details/prices; Admin approves the catalog for marketplace visibility. |

**FR 07 — Pick-Pack-Ready Workflow**
| | |
|---|---|
| Actors | Vendor (Staff) |
| Description | Structured staff workflow for picking items and marking orders ready for rider pickup. |
| Basic flow | Staff views "Reserved" orders, picks items, packs them, updates state to "Ready for Pickup". |

**FR 08 — Policy-Based Dispute Resolution**
| | |
|---|---|
| Actors | Admin, Customer, Vendor, Rider |
| Description | Resolves conflicts between users based on uploaded evidence and pre-defined platform rules. |
| Basic flow | User uploads photos/timestamps; Admin reviews evidence against policy to decide fund release or refund. |

**FR 09 — Real-time Order Notifications**
| | |
|---|---|
| Actors | All Users |
| Description | Automated alerts for order status changes and delivery task assignments. |
| Basic flow | System triggers SMS or in-app notifications whenever an order transitions to a new lifecycle state. |

### 3.2 Behaviour Requirements

*(No content was present under this heading in the source document — the table of contents references it, but the corresponding page numbers were left blank in the original, and no body text follows. Treated as missing content in the source, not a conversion artifact.)*

### 3.3 External Interface Requirements

*(Same as above — referenced in the table of contents with no page number, and no body content exists in the source document.)*

---

## 4. Other Non-Functional Requirements

### 4.1 Performance Requirements

Speed, efficiency, and scalability standards Vendra must maintain for a reliable user experience. Given the real-time nature of inventory sync, these metrics are critical to preventing "double-selling."

| ID | Title | Priority | Description | Rationale |
|---|---|---|---|---|
| PR 01 | Real-Time Inventory Synchronization | 1 (Critical) | Any stock change at the Vendor POS must reflect in the Customer marketplace within **3–5 seconds**. | Prevents "phantom stock" failures where a walk-in customer buys the last item while it still shows available online. |
| PR 02 | Order Reservation Latency | 1 (Critical) | "Checkout initiated" → "Stock Reserved" must complete in under **2 seconds**. | Fast reservation ensures transactional consistency and prevents two customers locking the same limited item simultaneously. |
| PR 03 | GPS Tracking Frequency | 2 (High) | Rider location must be transmitted to the server every **10 seconds** during an active task. | Needed for accurate "Distance"/"Wait Time" payout calculations and live order tracking. |
| PR 04 | Database Transaction Concurrency | 1 (Critical) | System must support at least **100 concurrent inventory requests/second** without stock ledger corruption. | Essential in a multi-vendor environment with many simultaneous vendor/customer actions at peak times. |
| PR 05 | Mobile Application Load Time | 2 (High) | Splash screen → functional dashboard transition must not exceed **5 seconds** on a standard 4G connection. | High-speed load times improve retention and let vendors process walk-in customers without delay. |
| PR 06 | Financial Calculation Accuracy | 1 (Critical) | Rider payouts and escrow releases must be calculated to the **nearest 0.01 currency unit** with zero rounding errors. | Precise calculations maintain trust with vendors/riders and keep commissions/fees aligned with platform policy. |

### 4.2 Safety and Security Requirements

Safeguards to prevent financial loss, data breaches, and operational harm; keeps transactions between customers, vendors, and riders transparent and protected.

| ID | Title | Priority | Description | Rationale | Action |
|---|---|---|---|---|---|
| SSR 01 | Authentication and Access Security | 1 (Critical) | All mobile and web sessions must be secured using JWT and RBAC. | Ensures riders cannot access vendor pricing and customers cannot view private shop data. | Encrypt all passwords and session tokens in the database. |
| SSR 02 | Escrow Financial Safety | 1 (Critical) | Funds must be held in a secure, immutable state until verified delivery occurs. | Prevents fraudulent direct payments; ensures customer trust by only releasing funds on physical verification. | Require the Rider app to verify GPS coordinates at the point of delivery before fund release. |
| SSR 03 | Data Integrity and Privacy | 1 (Critical) | The system must not store or transmit confidential personal info that violates local privacy laws. | Protects against legislative issues and maintains confidentiality of all personnel involved. | Log all state changes in an immutable stock ledger to prevent manual inventory tampering. |
| SSR 04 | Operational Safety (Buffer Stock) | 2 (High) | Enforce a "Public Stock" limit lower than actual physical inventory. | Safeguards the vendor against accidental overselling to walk-in customers when online orders are in progress. | Automatically deduct items from public visibility the moment an online checkout starts. |

### 4.3 Software Quality Attributes

- **4.3.1 Reliability** — Target 99.9% uptime for core transactional services, focused on inventory/financial data consistency. Achieved via automated DB transactions and atomic state-locking so inventory counts and escrow states are never corrupted under high concurrency. Verified via stress-testing with simulated concurrent walk-in + online orders.
- **4.3.2 Availability** — Marketplace and POS functions must stay accessible on mobile and the admin web dashboard during standard operating hours, via a lightweight Node.js backend in a cloud environment with automatic failover. Verified via periodic health checks on server response time and DB connectivity.
- **4.3.3 Maintainability (Design for Change)** — Code must be modular enough to support future extensions (new payment methods, third-party logistics) without a full rewrite, via decoupled Node.js services and a centralized Policy Engine that lets business rules update through the database rather than redeployment. Verified via code review and testing dynamic policy-variable adjustment independent of core logic.
- **4.3.4 Usability (User-Friendliness)** — The mobile interface should let a vendor complete a barcode-scan sale in under 10 seconds with minimal training, via a high-contrast, button-heavy UI optimized for fast-paced retail. Verified via field testing with local shopkeepers.
- **4.3.5 Robustness** — The system must handle unexpected errors (network drops, invalid input) without crashing or losing transactional data, via strict client-side validation plus thorough server-side verification on every API call. Verified via fault-injection testing (e.g., disconnecting network mid-checkout).
- **4.3.6 Portability** — Although the current implementation targets mobile + web admin, the infrastructure should stay platform-agnostic for future expansion, via a standardized React + Node.js stack. Verified by testing the backend on both Windows and Linux.

---

## 5. Design Description

### 5.1 Composite Viewpoint

Defines the high-level organizational structure: major design constituents and how they assemble into a cohesive, modular architecture, separating UI, business logic, and data storage into decoupled layers.

**5.1.1 Package Diagram (reconstructed from Figure 5.1)**

```
Package: UI
  Vendor POS Page | Customer Page | Rider Page | Admin Web Dashboard
        |
        v
Package: Controller
  Auth Manager -> Order Lifecycle -> Escrow Handler -> Policy Manager
        |
        v
Package: Model
  User / Product / Order / Inventory Ledger  --->  Database
```

**5.1.2 Logical Dependencies**

The system follows a strict hierarchical dependency flow: the **UI Package** interacts solely with the **Controller Package** to trigger operations (no direct/unauthorized DB access). The **Controller Package** validates requests against the **Policy Manager** before committing changes to the **Model Package**. This keeps the **Escrow Handler** and **Inventory Ledger** transactionally consistent across the marketplace.

### 5.2 Logical Viewpoint

Defines the system's static structure: core classes, attributes, methods, and relationships — the blueprint ensuring dual-inventory management and escrow security are structurally sound.

**5.2.1 Class Diagram (reconstructed from Figure 5.2)**

```
User
  - userID: int
  - email: string
  - role: string
  - jwtToken: string

Customer (extends User)
  + placeOrder()
  + trackDelivery()
  + cancelOrder()
  -> places -> Order (1..*)

Order
  - orderID: int
  - status: string
  - createdAt: timestamp
  + updateStatus()
  -> assigned to -> Rider (1)
  -> delivered_by -> Rider
  -> secured_by -> Escrow (1..1)

Vendor (extends User)
  - storeLocation: string
  + updateStock()
  + packOrder()
  -> manages -> Inventory

Rider (extends User)
  - gpsLocation: float
  + updateDeliveryState()

Escrow
  - heldAmount: float
  - status: string
  + releaseToVendor()
  + initiateRefund()

Inventory
  - productID: int
  - privateStock: int   (private/encapsulated)
  - publicStock: int    (public)
  + lockQuantity()
  + syncStock()
```

**5.2.2 Structural Relationships**

- **Generalization** — Vendor, Customer, and Rider classes inherit from the User class, reusing identity attributes like `jwtToken`.
- **Encapsulation** — The Inventory class marks `privateStock` as a private member, so physical stock can only change through controlled methods like `syncStock()`.
- **Associations** — Multiplicity is enforced for data integrity: a Customer can place multiple Orders (1 to *), but each Order is secured by exactly one Escrow instance (1 to 1).

### 5.3 Information Viewpoint

Defines the data structures and logical relationships needed to keep inventory levels and escrow balances consistent across the database.

**5.3.1 Entity Relationship Diagram** — *(Figure 5.3's OCR text was unrecoverable; no legible content remained. Its intent is described in 5.3.2 and matches the entities implemented in the database: `users`, `vendors`, `products`, `orders`, `order_items`, `inventory_locks`, `inventory_ledger`, `riders`, `wallet_ledger`, `platform_escrow_wallet`.)*

**5.3.2 Cardinality and Data Rules**

- **One-to-Many (1:N)** — A single User (Customer) can place multiple Orders over time; each Order is uniquely associated with the User who initiated it.
- **Many-to-Many (N:M)** — An Order can contain multiple Products, and a Product can appear in many Orders, requiring a mapping/junction table.
- **Dual Inventory Storage** — Storing `private_stock` and `public_stock` on the Product entity keeps physical shelf counts and digital marketplace availability linked at the database level.

### 5.4 Interaction Viewpoint

Defines the dynamic behavior of the system: how objects/actors collaborate over time, including the exchange of messages, concurrent tasks, and asynchronous triggers needed to keep the marketplace and physical inventory synchronized.

**5.4.1 Sequence Diagram — End-to-End Order Fulfillment (reconstructed from Figure 5.4)**

Participants: Customer, Customer App, Node.js Backend, Inventory DB, Escrow Handler, Vendor POS, Rider App.

```
Phase 1: Order Reservation
  Customer App  -> Backend: POST /api/orders/checkout
  Backend       -> Inventory DB: check Public Stock availability
  alt Stock Available
    Backend     -> Inventory DB: Lock Quantity (Reserve)
    Backend     -> Escrow Handler: set Escrow State = Pending
    Backend     -> Customer App: Push Notification (New Order Reserved)
  else Stock Unavailable
    Backend     -> Customer App: Error - Item Sold Out
  end

Phase 2: Fulfillment & Delivery
  Vendor POS    -> Backend: Pack Order
  Vendor POS    -> Backend: Mark as "Ready for Pickup"
  Backend       -> Rider App: Broadcast Delivery Task
  Rider App     -> Backend: Accept Task
  Rider App     -> Backend: Update Status - "On the Way"

Phase 3: Completion & Settlement
  Rider App     -> Customer: Handover Items
  Rider App     -> Backend: POST /api/delivery/complete (GPS-verified Confirm Delivery)
  Backend       -> Escrow Handler: Credit Rider Payout / Release Vendor Funds
  Backend       -> Customer App: Notify Customer - Delivered
```

**5.4.2 Behavioral Phases**

- **Phase 1: Order Reservation** — On checkout, the Node.js Backend synchronously checks the Inventory DB. If stock is valid, it executes a "Lock Quantity" command and moves the Escrow Handler to "Pending," preventing physical or digital overselling during the process.
- **Phase 2: Fulfillment & Delivery** — Asynchronous messaging: the Vendor POS broadcasts to the Rider App. The interaction stays in a transit state until the Rider accepts the task and physically picks up the items.
- **Phase 3: Completion & Settlement** — Triggered by a GPS-verified confirmation from the Rider. Only after this does the backend instruct the Escrow Handler to release funds to the Vendor and credit the Rider's payout, closing the loop securely.

### 5.5 State Dynamics Viewpoint

Captures how the Order, Inventory, and Escrow entities change status concurrently in response to real-world events and system triggers.

**5.5.1 State Machine (reconstructed from Figure 5.5 and 5.5.2)** — a single Checkout action drives three parallel state regions:

```
Order Fulfillment:   Reserved -> Packed -> ReadyForPickup -> Picked -> OnTheWay -> Delivered
Inventory Status:    Available -> ReservedLock -> (Delivered: permanently deducted)
                                              -> (Cancelled: released back to Available)
Escrow & Financials: PaymentPending -> FundsHeld -> FundsReleased (gated by Order == Delivered)
```

**5.5.2 State Transition Analysis**

- **Order Fulfillment** — Captures the physical journey of goods. Transitions like Picked → OnTheWay depend on external triggers (barcode scanning, GPS verification).
- **Inventory Status** — Manages item availability. When an order is Reserved, inventory enters a Reserved-Lock state so the physical item cannot be sold to a walk-in customer. Permanent deduction only happens on successful delivery.
- **Escrow & Financials** — Governs fund safety. Funds move PaymentPending → FundsHeld immediately on checkout. The transition to FundsReleased is strictly gated by the Order reaching Delivered.

### 5.6 Algorithm Viewpoint

**5.6.1 System Pseudo-code (reconstructed from Figure 5.6)**

```
ALGORITHM Vendra_Order_Lifecycle(CustomerID, VendorID, CartItems)
BEGIN
  // PHASE 1: PRE-CHECK & INVENTORY LOCKING
  FOR EACH item IN CartItems DO
    IF item.qty > item.PublicStock THEN
      SIGNAL 'Insufficient Stock'
      TERMINATE
    END IF
  END FOR

  INITIATE ATOMIC_TRANSACTION
    Inventory.Lock(CartItems, PrivateStock)
    Inventory.Hide(CartItems, PublicStock)
    Escrow.HoldFunds(Order.TotalAmount)
    Order.SetStatus('Reserved')
  COMMIT ATOMIC_TRANSACTION

  // PHASE 2: FULFILLMENT & RIDER LOGIC
  IF Vendor.Marks_Packed THEN
    Order.SetStatus('Ready_for_Pickup')
    Broadcast_Task_To_Riders(Radius = 5km)
  END IF

  IF Rider.Arrives_at_Destination THEN
    IF Distance(Rider.GPS, Customer.GPS) <= 200m THEN
      Order.SetStatus('Delivered')
      CALL Execute_Financial_Settlement()
    ELSE
      PROMPT 'Invalid Delivery Location'
    END IF
  END IF
END
```

**5.6.2 Procedural Strategy**

- **Atomic Transactions** — In Phase 1, locking physical inventory and holding escrow funds are treated as a single atomic unit, so inventory is never reserved unless payment is successfully initiated (prevents "phantom stock").
- **Geofencing Verification** — Phase 3 enforces a proximity check: the transition to "Delivered" (and the resulting fund release) is only possible if the Rider's GPS is within 200 meters of the Customer's designated location.
- **Policy-Driven Payouts** — `Execute_Financial_Settlement()` dynamically calculates payouts by fetching rates (Base, Distance, Wait time) from a centralized Policy Engine, for transparent and flexible financial management.

---

## Appendix A — Extracted Breakdown

### A.1 Features/Modules per Role

**Admin**
- Authentication & RBAC oversight (FR05)
- Policy & Governance Engine — commission, service charge, cancellation penalty, refund rule configuration (objective in §1.3; part of FR08's "pre-defined platform rules")
- Vendor approval/catalog approval (FR06)
- Dispute & Resolution Management — evidence review, fund release/refund decisions (FR08)
- Platform analytics/dashboard (KPI overview, financial auditing) (§2.3, §2.5.3)

**Vendor**
- Dual Inventory POS operations — Private/Public stock (FR01)
- Product catalog management — add/update products, pricing, categories (FR06)
- Pick-Pack-Ready workflow (FR07)
- Real-time stock ledger / stock-in/out history (§2.3)
- Walk-in POS sales (tablet) (§2.5.2)
- Staff roles: cashier, packer, inventory manager (§1.3)

**Customer**
- Digital storefront browsing — nearby stores, catalogs, availability (§2.3)
- Secure checkout with escrow payment (FR02, FR03)
- Order tracking and reviews / complaint submission (§2.3)
- Dispute submission with evidence (FR08)

**Rider**
- Task assignment — proximity/availability-based (§2.3)
- Delivery state management — Picked / On the Way / Delivered (§2.3)
- GPS-based payout tracking (FR04)
- Delivery confirmation gated by geofence (200m) (§5.6.2)

### A.2 Shared Backend Responsibilities

- Authentication & JWT session issuance, RBAC enforcement (FR05, SSR01)
- Dual-inventory calculation engine: `public_stock = private_stock - buffer - reserved` (FR01, SSR04)
- Order reservation/locking with atomic transactions (FR02, PR02, PR04)
- Escrow ledger: hold → release/refund (FR03, SSR02)
- Rider payout calculation from GPS + Policy Engine rates (FR04, PR06)
- Policy Engine — dynamic, DB-driven business rules (§1.3, §4.3.3)
- Dispute resolution workflow/state (FR08)
- Notification dispatch — SMS/in-app on lifecycle transitions (FR09)
- Immutable inventory/stock ledger for auditing (SSR03)

### A.3 Data Models / Entities

Derived from §5.2–5.3 and cross-checked against the implemented schema (`backend/init.sql`):

| Entity | Key Attributes | Notes |
|---|---|---|
| User | id, email, role (customer/vendor/rider/admin), jwtToken/password_hash | Base identity; role drives RBAC |
| Vendor | store location, approval status | 1:1 with User (role=vendor) |
| Rider | vehicle type, availability, gpsLocation | 1:1 with User (role=rider) |
| Product / Inventory | privateStock (private), publicStock, buffer, reserved_quantity | Dual-inventory core |
| Order | status, totalAmount, timestamps | 1 Customer : many Orders; many Products : many Orders via order items |
| Escrow | heldAmount, status (Pending/FundsHeld/FundsReleased) | 1:1 with Order |
| Inventory Ledger | change_type, quantity_change, before/after stock | Immutable audit trail (SSR03) |
| Wallet / Wallet Ledger | balance, transaction_type | Vendor/customer wallet movements incl. escrow release |
| Policy (Engine) | rule type, parameters | Not present as a distinct entity in source diagrams beyond narrative mentions — no concrete attribute list given in the SRDS |

### A.4 Workflows / State Machines

1. **Order Reservation → Fulfillment → Settlement** (three-phase sequence, §5.4) — the primary end-to-end workflow.
2. **Order Fulfillment states**: Reserved → Packed → ReadyForPickup → Picked → OnTheWay → Delivered (or → Cancelled).
3. **Inventory states**: Available → ReservedLock → Deducted (on Delivered) | released back to Available (on Cancelled).
4. **Escrow states**: PaymentPending → FundsHeld → FundsReleased (gated on Order.Delivered) | Refunded (dispute outcome).
5. **Dispute workflow**: evidence submission (photo + timestamp) → Admin review against policy → fund release or refund decision (FR08).
6. **Rider payout algorithm**: triggered on delivery confirmation; geofence check (≤200m) → `Execute_Financial_Settlement()` reads Base/Distance/Wait-time rates from the Policy Engine → credits rider, releases vendor funds.

---

## Appendix B — Gaps in the Source Document Itself

These are not conversion artifacts — the content is genuinely absent from the original SRDS:

- **§3.2 Behaviour Requirements** and **§3.3 External Interface Requirements** are listed in the Table of Contents but have no body content and no page number in the source (the ToC row's page number cell is blank for both).
- **Figure 5.3 (ERD)** — the image's OCR text was unrecoverable (garbled beyond reconstruction); no legible fragment survived. Its intended entities are inferable from §5.3.2's prose and from the implemented database schema (see Appendix A.3), but the actual diagram content/layout is lost.
- **Table 3.4** in the original Table of Tables lists "FR 03 – Escrow Fund Management" at page 68, and **Table 3.6** lists "FR 05 – Secure Role-Based Login" at page 69 — both clearly wrong given the document is 33 pages long; likely leftover placeholder page numbers from a template. Not corrected in the body text since the actual FR03/FR05 tables appear correctly on pages 18–19 in sequence.
