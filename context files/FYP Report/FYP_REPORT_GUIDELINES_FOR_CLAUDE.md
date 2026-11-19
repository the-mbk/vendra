# VENDRA — Final Year Project (FYP) Report Master Guidelines
## Comprehensive Instructions for Claude Pro to Generate the Official Final Report

> **Target File to Produce/Format:** `D:\FYP\context files\FYP Report\Vendra-FYP-Report-FINAL.docx`  
> **Based On:** `Vendra-FYP-Report-DRAFT.docx` and University Templates  
> **Academic Institution:** COMSATS University Islamabad, Wah Campus  
> **Department:** Department of Computer Science  
> **Project Title:** Vendra: A Multi-Vendor Digital Marketplace for Global Commerce  
> **Supervised By:** Dr. Muhammad Sharif  
> **Students:** Muhammad Bilal (SP23-BCS-045), Zohaib Khan (SP23-BCS-088)

---

## 1. Core Directives & User Feedback to Fix

The existing draft (`Vendra-FYP-Report-DRAFT.docx`) has solid foundation content, but has three major flaws that Claude Pro must systematically correct:

### 1.1 Table Styling: Academic Monochrome (NOT Colorful Web Tables)
- ❌ **Forbidden:** Bright blue, purple, orange, or green table header backgrounds, gradient fills, and website-style borders.
- ✅ **Required:** Strict formal academic IEEE/university standard table formatting:
  - Header row: Black text, bold, with light gray background shading (e.g., `#EFEFEF` or 10–15% gray tint) and a solid top and bottom border.
  - Body cells: Plain white background, black text (Times New Roman 11pt or 12pt).
  - Borders: Thin horizontal borders (`0.5pt` or `0.75pt` black/dark gray). Minimal or no vertical gridlines (academic book-tabs style is preferred).
  - Table Caption: **Always PLACED ABOVE the table**, bolded:  
    `Table 2.1: Operating Environment Specification`
  - Text alignment: Left-aligned for text, center-aligned for IDs/dates/codes, right-aligned for monetary/numeric values.

### 1.2 Figures: Real System Screenshots (No Skipped Figures or Placeholders)
- ❌ **Forbidden:** Empty boxes, "Insert Figure Here" text, or skipped screenshots.
- ✅ **Required:** Claude must instruct or use real, high-resolution screenshots captured directly from the running Vendra ecosystem:
  - Run the local environment using `powershell -ExecutionPolicy Bypass -File .\run-local.ps1`.
  - Capture real screens from the active apps:
    - **Customer App** (`http://localhost:5001`)
    - **Vendor POS App** (`http://localhost:5002`)
    - **Rider App** (`http://localhost:5003`)
    - **Admin Web Dashboard** (`http://localhost:3001`)
    - **Vendra Pay Gateway Sandbox** (`http://localhost:4242`)
  - Figure Caption: **Always PLACED BELOW the figure**, centered, bolded:  
    `Figure 4.3: Vendor POS Dual-Inventory Management and Active Reservations`
  - All figures must be referenced in the body text *before* they appear (e.g., *"As illustrated in Figure 3.4, the checkout sequence initiates an escrow lock..."*).

### 1.3 Writing Tone: Humanized, Natural Academic Engineering (No AI Buzzwords)
- ❌ **Forbidden AI Clichés:** "In this fast-paced digital era...", "A game-changing paradigm...", "Delve into...", "Testament to...", "Paving the way...", "Seamless integration...", "Crucial milestone...".
- ✅ **Required:** Rigorous, sober, authentic engineering English. Write from the perspective of two senior computer science students presenting their architectural decisions, trade-offs, concurrency race-condition solutions, and validation results.

---

## 2. University Formatting Rules (COMSATS Template Compliance)

Claude Pro must enforce these exact rules from `D:\FYP\context files\FYP Report\FYP-Repor-Template-Guidelines\Guidelines for FYP Report.docx`:

| Attribute | Official COMSATS Standard |
|---|---|
| **Paper Size** | A4 (`210 mm × 297 mm`), minimum 70g white offset paper |
| **Margins** | Top: `1.0 inch` (`2.54 cm`), Bottom: `1.0 inch`, Right: `1.0 inch`, **Left (Binding Side): `1.5 inches` (`3.81 cm`)** |
| **Typeface / Font** | **Times New Roman** exclusively throughout the entire manuscript |
| **Font Sizes** | - Main Body Text: `12 pt`<br>- Major Headings (Heading 1): `16 pt`, Bold, ALL CAPS<br>- Sub-headings (Heading 2): `14 pt`, Bold<br>- Sub-sub-headings (Heading 3): `12 pt`, Bold<br>- Footnotes / Table text: `10 pt` |
| **Line Spacing** | `1.5 lines` for body text. Single spacing for block quotes, footnotes, and table cells |
| **Paragraph Alignment**| **Fully Justified** (`Ctrl+J`) |
| **Page Borders** | **NO borders** on any page |
| **Page Numbering** | - Preliminary Pages (Abstract to Abbreviations): Lowercase Roman numerals (`i, ii, iii...`), centered at bottom. Title page is page `i` but unprinted.<br>- Main Body & Appendices: Arabic numerals (`1, 2, 3...`), centered at bottom, starting at `1` on Chapter 1 Introduction. |
| **Figure Numbering** | Chapter-based: `<Figure Chapter#.Figure#: Caption>` placed **BELOW** figure |
| **Table Numbering** | Chapter-based: `<Table Chapter#.Table#: Caption>` placed **ABOVE** table |

---

## 3. Comprehensive Report Chapter Structure

The report must strictly follow `01-Template-FYP-Report-PartA-IntroPages.docx` and `02-Template-FYP-Report-PartB-Chapters.docx`:

### PART A: INTRODUCTORY PAGES
1. **Title Page:** Exact format with university crest, title, student names/reg numbers, supervisor, and date.
2. **Declaration of Originality:** Signed statement confirming no plagiarism.
3. **Certificate of Approval:** Formal approval sheet signed by External Examiner, Supervisor (Dr. Muhammad Sharif), and HoD.
4. **Dedication:** Optional personal dedication.
5. **Acknowledgements:** Formal thanks to supervisor, faculty, and families.
6. **Abstract:** Concise 250–300 word executive summary detailing the problem (phantom stock, payment distrust in Pakistan), proposed solution (Vendra Dual-Inventory POS + Escrow), methodology, and empirical test results (132 backend tests, 237 frontend tests passing).
7. **Table of Contents:** Automated hierarchical TOC with dot leaders.
8. **List of Figures:** Automated list with figure numbers, captions, and page numbers.
9. **List of Tables:** Automated list with table numbers, captions, and page numbers.
10. **Abbreviations Table:** Complete table containing API, ERD, FR, GPS, JWT, POS, RBAC, SDA, SME, SSR, UML, etc.

---

### PART B: MAIN CHAPTERS

#### CHAPTER 1: INTRODUCTION
* **1.1 Chapter Preamble:** Brief summary introducing what the reader will find in Chapter 1.
* **1.2 System Introduction:** Vendra as a specialized multi-vendor digital marketplace and operational retail backbone designed specifically for Pakistan’s retail ecosystem.
* **1.3 Background of the System:** Contemporary analysis of Daraz and Foodpanda in Pakistan. Why order failures occur (shopkeepers selling physical items while listed online; manual inventory reconciliation; distrust in online prepayments leading to 85%+ Cash-on-Delivery with high return-to-origin rates).
* **1.4 Objectives of the System:**
  - Elimination of phantom stock through Dual Inventory POS.
  - SME digital empowerment with zero-cost Point of Sale.
  - Trust-based escrow payment ecosystem holding funds until verified physical handover.
  - Transparent GPS-calculated compensation for delivery fleet (distance + waiting time).
  - Dynamic policy-based platform governance.
* **1.5 Significance of the System:** Economic and operational impact on Pakistani retail, reduction of e-commerce returns, and consumer trust enhancement.

---

#### CHAPTER 2: REQUIREMENT SPECIFICATIONS
* **2.1 Chapter Preamble**
* **2.2 Product Scope:** Boundaries of the system. What Vendra does (instant hyperlocal fulfillment, real-time POS stock locking, escrow mediation, GPS tracking) and what it intentionally excludes (long-haul cross-country shipping, third-party centralized warehousing).
* **2.3 Product Description:**
  - *2.3.1 Product Perspective:* High-level System Context Diagram showing Cloud Backend, PostgreSQL, SeaweedFS S3 storage, Vendra Pay / Stripe gateways, Next.js Admin dashboard, and Flutter mobile apps.
  - *2.3.2 Product Functionality:* Grouped functional breakdown (Administrative & Security, Vendor POS & Inventory, Customer Marketplace, Rider Delivery).
  - *2.3.3 Users and Characteristics:* Personas for SME Vendor, Retail Customer, Hyperlocal Rider, and Platform Administrator.
  - *2.3.4 Operating Environment:* Table detailing Android (Flutter), Web (Next.js 14 / React), Backend runtime (Node.js 20+), Database (PostgreSQL 16 Alpine), and Docker virtualization.
* **2.4 Specific Requirements:**
  - *2.4.1 Functional Requirements (FR 01 to FR 09):* Detailed specification tables with Actor, Description, Preconditions, Basic Flow, Alternate Flows, and Concurrency Risks for:
    - **FR 01:** Dual Inventory Synchronization (Private vs. Public Stock).
    - **FR 02:** Real-Time Order Reservation (Instant inventory lock upon checkout).
    - **FR 03:** Escrow Fund Management (State machine: Held ➔ Released / Refunded / Disputed).
    - **FR 04:** GPS-Based Rider Payout Calculation (Formula: $\text{Base} + (\text{Dist} \times \text{Rate}) + (\text{Wait} \times \text{Rate})$).
    - **FR 05:** Secure Role-Based Access Control (JWT sessions with role claims).
    - **FR 06:** Product Catalog Management.
    - **FR 07:** Pick-Pack-Ready Verification Workflow.
    - **FR 08:** Policy-Based Dispute Resolution.
    - **FR 09:** Real-Time Order Notifications.
  - *2.4.2 Behavioral Requirements (Use Cases):* System-level Use Case Diagram plus fully dressed use case specifications for Checkout, POS Walk-in Sale, and Delivery Handover.
  - *2.4.3 External Interface Requirements:* Detailed specifications for User Interfaces, Hardware Interfaces (Smartphone GPS, Camera Barcode Scanner), and Software APIs (Stripe / Vendra Pay, OpenStreetMap / Flutter Map).
* **2.5 Other Non-Functional Requirements:**
  - Performance Requirements (PR 01: Inventory Sync < 3s, PR 02: Reservation Latency < 2s, PR 03: GPS frequency 10s, PR 04: Concurrency 100 req/s, PR 05: Mobile Load < 5s, PR 06: Currency Precision to 0.01 Rs).
  - Safety and Security Requirements (SSR 01: Delivery PIN non-repudiation, SSR 02: JWT encryption, SSR 03: Idempotent payment webhooks).
  - Software Quality Attributes (Maintainability, Reliability, Portability, Usability).

---

#### CHAPTER 3: DESIGN SPECIFICATIONS
* **3.1 Chapter Preamble**
* **3.2 Architectural Viewpoint:**
  - *Package Diagram (Logical):* Modular structure showing Clean Architecture layers (Presentation, BLoC State Management, Services, Repository, Data Access).
  - *Deployment Diagram (Physical):* Docker containers topology (`vendra-db`, `vendra-storage`, `vendra-pay`, Node.js Express server, and client endpoints).
* **3.3 Logical Viewpoint:**
  - *Class Diagrams:* Core entity relationships in backend and Flutter client models.
  - *Entity Relationship Diagram (ERD):* Complete relational database schema (13 migrations applied: `users`, `vendors`, `products`, `orders`, `order_items`, `inventory_ledgers`, `payments`, `withdrawals`, `disputes`, `dispute_evidence`, `policies`).
* **3.4 Interaction Viewpoint (Sequence Diagrams):**
  - Sequence Diagram 1: Online Order Placement & Dual-Inventory Reservation Locking.
  - Sequence Diagram 2: Walk-in POS Sale & Inventory Buffer Deduction.
  - Sequence Diagram 3: Rider Geofence Arrival, Doorstep PIN Verification, and Escrow Release.
  - Sequence Diagram 4: Customer Dispute Filing, Escrow Freezing, and Admin Resolution.
* **3.5 Detailed Design & Algorithms:**
  - State Machine Diagram: Order Lifecycle (`pending` ➔ `reserved` ➔ `ready_for_pickup` ➔ `assigned` ➔ `picked` ➔ `on_the_way` ➔ `delivered` / `cancelled` / `disputed`).
  - Escrow Release Algorithm (Pseudo-code demonstrating time-bound release and OTP verification).
  - Rider Compensation Calculation Algorithm (Handling straight-line vs GPS trail and grace-period subtraction).

---

#### CHAPTER 4: IMPLEMENTATION & USER INTERFACES
* **4.1 Chapter Preamble**
* **4.2 Implementation Technologies & Tools:** Justification for Flutter (cross-platform single codebase), Node.js/Express (asynchronous I/O for real-time inventory updates), PostgreSQL (ACID compliance for escrow transactions), Docker Compose (deterministic reproducible environments), and SeaweedFS (S3-compatible local asset storage).
* **4.3 Database Migrations & Ledger Schema:** Overview of progressive schema migrations (`001_initial.sql` to `013_store_photos.sql`).
* **4.4 User Interface Walkthrough & Screenshots:**
  *(Must contain real screenshots with academic captions below each figure)*
  - *Figure 4.1:* Customer Marketplace Home & Thematic Categories.
  - *Figure 4.2:* Customer Multi-Store Cart & Escrow Prepayment Checkout.
  - *Figure 4.3:* Customer Live Order Tracking, Map Geofence, and Handover PIN Card.
  - *Figure 4.4:* Vendor POS Walk-in Sale Interface with Quick-Tender Cash Buttons.
  - *Figure 4.5:* Vendor Dual-Inventory Management (Private, Buffer, Reserved, Public).
  - *Figure 4.6:* Vendor Pick-Pack-Ready Interactive Checklist.
  - *Figure 4.7:* Rider Active Task Screen with Live Store Waiting Timer.
  - *Figure 4.8:* Rider Payout Slip with Itemized Distance and Wait Time Earnings.
  - *Figure 4.9:* Admin Governance Dashboard with POS vs. Online Revenue Metrics.
  - *Figure 4.10:* Admin Multi-Evidence Dispute Forensic Dossier.
  - *Figure 4.11:* Admin Dynamic Policy Engine Simulator.

---

#### CHAPTER 5: TESTING & QUALITY ASSURANCE
* **5.1 Chapter Preamble**
* **5.2 Testing Strategy & Test Environments:** Unit testing, widget testing, API integration testing, and Docker regression suites.
* **5.3 Test Execution Summary:**
  - Backend API Tests: 132 automated test suites (Jest/Supertest) verifying escrow locks, concurrency race conditions, and Stripe/Payoneer webhooks.
  - Frontend Client Tests: Customer (82 tests), Vendor (81 tests), Rider (74 tests) — all passing.
* **5.4 Requirement Traceability Matrix (RTM):** Formal academic matrix mapping each FR (FR 01 to FR 09) to exact Test Case IDs and pass/fail statuses.
* **5.5 Detailed Test Cases:** Formal academic tables detailing Test Case ID, Title, Preconditions, Input Data, Expected Output, Actual Result, and Status (Pass/Fail) for:
  - TC 01: Concurrent POS walk-in sale vs online order reservation.
  - TC 02: Escrow lock enforcement during order cancellation timeout.
  - TC 03: Rider handover PIN verification failure vs success.
  - TC 04: Rider waiting time compensation calculation past 5-minute grace threshold.
  - TC 05: Photographic evidence upload and escrow freeze during dispute initiation.

---

#### CHAPTER 6: CONCLUSION & FUTURE WORK
* **6.1 Chapter Preamble**
* **6.2 Conclusion:** Summary of achieved objectives. How Vendra proves that solving structural inventory sync and payment escrow eliminates the primary root causes of e-commerce failure in developing economies.
* **6.3 Limitations of Current System:** Reliance on GPS accuracy in ultra-dense historic bazars; lack of offline SQLite POS sync during complete multi-hour power/internet outages.
* **6.4 Future Work & Extensions:**
  - Edge-device offline POS synchronization with conflict-free replicated data types (CRDTs).
  - AI-driven predictive demand forecasting forkiryana store buffers based on local neighborhood seasonality.
  - Native integration with 1Link / Raast instant national payment rails.

---

### REFERENCES
- Minimum 25–30 academic papers, software engineering standards, and industry reports formatted in strict **IEEE style** (e.g., IEEE Std 830-1998, State Bank of Pakistan E-Commerce Reports, ACM/IEEE papers on distributed transactions and inventory management).
