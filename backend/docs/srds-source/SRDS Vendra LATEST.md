# **Software Requirements and Design Specifications** 



<!-- Start of picture text -->
~c, UNJ pr<br>oS ~<br>4H enue” %<br><!-- End of picture text -->

## **Vendra: A Multi-Vendor Digital Marketplace for Global Commerce** 

|**Name**|**Registration Number**|
|---|---|
|**Muhammad Bilal**|SP23-BCS-045|
|**Zohaib Khan**|SP23-BCS-088|



#### **Supervised By: Dr. Muhammad Sharif** 

### **COMSATS University of Information Technology Wah Campus** 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 2_** 

## **<mark>Table of Contents</mark>** 

|**CONTE**|**NTS ................................................................................................................................................................. 2**|
|---|---|
|**1**<br>**IN**|**TRODUCTION.............................................................................................................................................. 6**|
|1.1|SYSTEMINTRODUCTION.............................................................................................................................. 6|
|1.2|BACKGROUND OF THESYSTEM................................................................................................................... 6|
|1.3|OBJECTIVES OF THESYSTEM....................................................................................................................... 6|
|1.4|SIGNIFICANCE OF THESYSTEM.................................................................................................................... 7|
|**2**<br>**OV**|**ERALL DESCRIPTION ............................................................................................................................. 8**|
|2.1|PRODUCTPERSPECTIVE............................................................................................................................... 8|
|2.2|PRODUCTSCOPE......................................................................................................................................... 9|
|2.3|PRODUCTFUNCTIONALITY.......................................................................................................................... 9|
|2.4|USERS ANDCHARACTERISTICS................................................................................................................. 10|
|2.5|OPERATINGENVIRONMENT....................................................................................................................... 11|
|**3**<br>**SP**|**ECIFIC REQUIREMENTS ....................................................................................................................... 17**|
|3.1|FUNCTIONALREQUIREMENTS................................................................................................................... 17|
|3.2|BEHAVIOURREQUIREMENTS.........................................................................................................................|
|3.3|EXTERNALINTERFACEREQUIREMENTS........................................................................................................|
|**4**<br>**OT**|**HER NON-FUNCTIONAL REQUIREMENTS...................................................................................... 20**|
|4.1|PERFORMANCEREQUIREMENTS................................................................................................................ 20|
|4.2|SAFETY ANDSECURITYREQUIREMENTS................................................................................................... 21|
|4.3|SOFTWAREQUALITYATTRIBUTES............................................................................................................ 23|
|**5**<br>**DE**|**SIGN DESCRIPTION................................................................................................................................ 25**|
|5.1|COMPOSITEVIEWPOINT............................................................................................................................ 25|
|5.2|LOGICALVIEWPOINT................................................................................................................................ 26|
|5.3|INFORMATIONVIEWPOINT........................................................................................................................ 28|
|5.4|INTERACTIONVIEWPOINT......................................................................................................................... 29|
|5.5|STATEDYNAMICSVIEWPOINT.................................................................................................................. 30|
|5.6|ALGORITHMVIEWPOINT........................................................................................................................... 31|



**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 3_** 

## **<mark>Table of Figure</mark>** 

|FIGURE 2.1 _SYSTEMCONTEXTDIAGRAM FORVENDRADIGITALMARKETPLACE_......................................................... 8|
|---|
|FIGURE 2.2 _LOGINMOBILE_.................................................................................................................................... 11|
|FIGURE 2.3 _PRODUCTDETAILMOBILE_................................................................................................................... 11|
|FIGURE 2.4 _CUSTOMERHOMEPAGEMOBILE_.......................................................................................................... 12|
|FIGURE 2.5 _DISPUTESUBMISSIONMOBILE_............................................................................................................. 12|
|FIGURE 2.6 _ORDERTRACKINGMOBILE E_................................................................................................................ 13|
|FIGURE 2.7 _RIDERHOMEMOBILE_.......................................................................................................................... 13|
|FIGURE 2.8 _POS SCREENTABLET_........................................................................................................................... 14|
|FIGURE 2.9 _ADMINDASHBOARDWEB_..................................................................................................................... 15|
|FIGURE 2.10 _CUSTOMERHOMEPAGEWEB_............................................................................................................. 16|
|FIGURE 2.11 _VENDORDASHBOARDWEB_................................................................................................................ 16|
|FIGURE 5.1 _PACKAGEDIAGRAM FORVENDRA SHOWINGUI, CONTROLLER, ANDMODELLAYERS_.............. 26|
|FIGURE 5.2 _COMPLETECLASSDIAGRAM FORVENDRA SHOWING STATIC RELATIONSHIPS_............................ 27|
|FIGURE 5.3 _ERD FORVENDRA SHOWING TRANSACTIONAL RELATIONSHIPS AND ATTRIBUTES_...................... 28|
|FIGURE 5.4 _SEQUENCEDIAGRAM FORVENDRA SHOWING THE THREE PHASES OF ORDER FULFILLMENT_... 29|
|FIGURE 5.5 _CONCURRENTSTATEMACHINEDIAGRAM FORVENDRASYSTEM_................................................ 31|
|FIGURE 5.6 _INTEGRATEDSYSTEMPSEUDO-CODE FORORDERLIFECYCLE ANDFINANCIALSETTLEMENT_.. 32|



**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 4_** 

## **<mark>Table of Tables</mark>** 

|TABLE3.1 _OPERATINGENVIRONMENT_...................................................................................................................... 11|
|---|
|TABLE3.2 _FR 01 – DUALINVENTORYSYNCHRONIZATION_......................................................................................... 17|
|TABLE3.3 _FR 02 – REAL-TIMEORDERRESERVATION_............................................................................................... 18|
|TABLE3.4 _FR 03 – ESCROWFUNDMANAGEMENT_.................................................................................................... 68|
|TABLE3.5 _FR 04 – GPS-BASEDRIDERPAYOUT_....................................................................................................... 19|
|TABLE3.6 _FR 05 – SECUREROLE-BASEDLOGIN_ ..................................................................................................... 69|
|TABLE3.7 _FR 06 – PRODUCTCATALOGMANAGEMENT_............................................................................................ 19|
|TABLE3.8 _FR 07 –  PICK-PACK-READYWORKFLOW_................................................................................................ 20|
|TABLE3.9 _FR 08 –  POLICY-BASEDDISPUTERESOLUTION_....................................................................................... 20|
|TABLE3.10 _FR 09 –  REAL-TIMEORDERNOTIFICATIONS_.......................................................................................... 20|
|TABLE4.1 _PR 01 – REAL-TIMEINVENTORYSYNCHRONIZATION_................................................................................. 21|
|TABLE4.2 _PR 02 – ORDERRESERVATIONLATENCY_................................................................................................. 21|
|TABLE4.3 _PR 03 – GPS TRACKING ANDUPDATEFREQUENCY_................................................................................. 21|
|TABLE4.4 _PR 04 – DATABASETRANSACTIONCONCURRENCY_.................................................................................... 22|
|TABLE4.5 _PR 05 – APPLICATIONLOAD ANDRESPONSETIME_................................................................................... 22|
|TABLE4.6 _PR 06 – PAYOUTCALCULATIONINTEGRITY_.............................................................................................. 22|
|TABLE4.7 _SSR 01 – AUTHENTICATION ANDACCESSSECURITY_.................................................................................. 23|
|TABLE4.8 _SSR 02 – ESCROWFINANCIALSAFETY_...................................................................................................... 23|
|TABLE4.9 _SSR 03 – DATAINTEGRITY ANDPRIVACY_.................................................................................................. 23|
|TABLE4.10 _SSR 04 – OPERATIONALSAFETY(BUFFERSTOCK)_................................................................................. 24|



**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 5_** 

||**List of Abbreviation/Acronym **|
|---|---|
|**API**|Application Programming Interface|
|**ERD**|Entity Relationship Diagram|
|**FR**|Functional Requirement|
|**GPS**|Global Positioning System|
|**JWT**|JSON Web Tokens|
|**POS**|Point of Sale|
|**RBAC**|Role-Based Access Control|
|**SDA**|Software Design and Architecture|
|**SME**|Small-to-Medium Enterprise|
|**SSR**|Safety and Security Requirement|
|**UML**|Unified Modeling Language|



**_Page 6_** 

**_Software Requirements Specification & Design Description for Vendra_** 

## **<mark>1. Introduction</mark>** 

#### **1.1 System Introduction** 

Vendra is a role-based, multi-vendor e-commerce and delivery platform that aims to address the structural operational challenges of the digital marketplace in Pakistan. The system acts as a central point where customers, vendors, riders and an organization/admin can securely access the system based on their roles. The main innovation is the combination of a Vendor POS which handles "Dual Inventory" (private actual stock for physical store and public visible stock for online customers). 

#### **1.2 Background of the System** 

In today's Pakistani market, there are online platforms such as Daraz or Foodpanda that often experience what is known as "order failures" when the vendors do not keep the inventory updated in real-time on both the online platform and the physical store. There are no affordable, integrated tools for vendors to handle walk-in sales and digital orders. Vendra's solution is to offer a single POS solution that streamlines inventory management and introduces an escrow system to build trust between the buyer and the seller. 

#### **1.3 Objectives of the System** 

The main objective of Vendra is to establish a harmonized, trusted digital marketplace by the following specific objectives: 

- **Reduction of Order Cancellations and Failures:** To overcome the "phantom stock" issue with the online availability of physical shop stock, by integrating a real-time Vendor POS. This way, customers will only see and order what is available in the store. 

- **Digitization of SME Vendors:** To offer small-to-medium enterprises a low-cost web-based pointof-sale solution to manage inventory, pricing, and staff roles (cashier, packer, inventory manager) without the need for costly third-party software. 

- **Implementation of a Trust Based Payment Ecosystem:** To establish an Escrow-based mechanism where the platform will hold customer payments and release them to the vendors only after successful delivery or dispute resolution. This reduces the chance of fraud and boosts the trust of the buyer. 

- **Optimization of Delivery Operations:** To create a structured own-fleet rider management system which will track the delivery state (picked, on the way, delivered) and ensure Fair Rider Compensation. The payouts are determined by a clear formula that takes into account base fees, distance traveled, and waiting times. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 7_** 

- **Enabling Policy-Driven Governance:** To remove hard-coding of logic and implement a configurable Policy Engine. This enables the Admin to create and modify cancellation, penalty, service and dispute resolution rules dynamically. 

- **Structural Inventory Accuracy (Dual Inventory):** To keep both Private Stock (actual physical count) and Public Stock (visible online quantity) in the system to ensure high level of operational precision. This enables vendors to maintain a safety margin for walk-in customers and serve online customers. 

- **Role Based Accountability:** To have secure and distinct workflows for each actor (Admin, Vendor, Rider and Customer) with a strong RBAC (Role Based Access Control) system. 

#### **1.4 Significance of the System** 

The system is important because it digitizes small vendors who have no license fees, and they will have a "shop brain" that will not allow them to over-sell. It provides a safe environment for customers to purchase, ensuring their payments are secure, and a clear and transparent payout structure for riders. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 8_** 

## **<mark>2 Overall Description</mark>** 

#### **2.1 Product Perspective** 

Vendra is an all-new digital ecosystem built specifically for a mobile-first retail environment. It's not a replacement for an existing product, but rather a contemporary solution for small-tomedium enterprises (SMEs) that are struggling with manual, disconnected sales processes for physical and digital sales. The idea behind the product was born out of a problem in Pakistan called "phantom stock" where a shop's physical stock and online store are not synchronized leading to frequent cancellations of orders. Vendra is the "brain of the shop," connecting walk-in and digital marketplace users through a centralized operation on a specialized Android-based POS. 



<!-- Start of picture text -->
(_ Vendor}<br>EE/We Browser<br>oo” Vendra Digital Marketplace (Cloud/ Web Environment)<br>| Internal Subsystems V<br>Customer Module POSSubsystem & Inventory<br>thiNeagenai Mobile Tracking f<br>|<br>\<br>c et)<br>{ System | v<br>\Nay,Admin} Escrow & Payment Policy& Dispute Engine Notification Module Rider Module<br>‘Admin Dashboard<br>Authentication & RBAC<br><!-- End of picture text -->

_Figure 2.1: System Context Diagram for Vendra Digital Marketplace_ 

**_Page 9_** 

**_Software Requirements Specification & Design Description for Vendra_** 

#### **2.2 Product Scope** 

The scope of **Vendra** is centered on establishing a high-integrity, mobile-first operational backbone for multi-vendor commerce, optimized exclusively for the **Android platform** . The software is designed to manage the end-to-end lifecycle of a transaction from the moment a vendor scans a physical item into their inventory via their smartphone until a rider confirms delivery and funds are released from escrow. By focusing on the "broken backbone" of current marketplaces, the system primarily addresses inventory synchronization and trustbuilding through a unified mobile infrastructure. 

#### **2.3 Product Functionality** 

The platform is designed to provide a seamless experience that bridges physical retail operations with digital commerce across **mobile devices** for primary users and a **web interface** for administrative oversight. The system's major functions are organized by the primary user roles to ensure high-level clarity: 

- **Core Administrative & Security Functions:** 

   - **Authentication & Role-Based Access (RBAC)** : Securely authenticates all users via JWT sessions, granting specific permissions for Admins, Vendors, Riders, and Customers. 

   - **Policy & Governance Engine** : Enables the Admin to configure platform-wide rules for commission fees, service charges, cancellation penalties, and refund logic via a web dashboard. 

   - **Dispute & Resolution Management** : Provides a structured workflow for resolving conflicts using photo evidence and timestamps uploaded through mobile apps. 

   - **Vendor & Inventory Functions (Mobile Interface)** 

   - **Dual Inventory POS Operations** : Allows vendors to perform walk-in sales and manage stock using a mobile interface that tracks both **Private Stock** (actual physical count) and **Public Stock** (customer-visible quantity). 

   - **Automated Order Reservation** : Instantly "locks" inventory items in the POS when an online order is placed, preventing accidental double-selling to walk-in customers. 

   - **Pick-Pack-Ready Workflow** : Guides vendor staff through picking items and packing orders, updating the status to "Ready for Pickup" to trigger rider assignment. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 10_** 

   - **Real-Time Stock Ledger** : Maintains a digital history of all "Stock In" and "Stock Out" events for auditing and inventory accuracy. 

   - **Customer Marketplace Functions (Mobile Interface)** 

   - **Digital Storefront Browsing** : Allows customers to view nearby stores, browse product catalogs, and check real-time availability based on vendor policy rules. 

   - **Secure Checkout & Escrow Payment** : Facilitates order placement where funds are held in a secure escrow state rather than being paid directly to the vendor initially. 

   - **Order Tracking & Reviews** : Provides customers with live updates on order status and allows for post-delivery reviews or complaint submissions. 

- **Rider & Delivery Functions (Mobile Interface):** 

   - **Task Assignment** : Delivers real-time task notifications to riders based on their availability and proximity to "Ready" orders. 

   - **Delivery State Management** : Enables riders to update the progress of an order (Picked, On the Way, Delivered) via their mobile device. 

   - **GPS-Based Payout Tracking** : Automatically calculates rider earnings for each task based on a formula considering base fees, distance travel, and waiting times. 

#### **2.4 Users and Characteristics** 

**2.4.1 Vendors** : Shop owners with basic technical literacy who use the mobile interface for high-frequency tasks like barcode scanning, inventory management, and digital order processing. They are critical to the system as they provide the real-time stock data required to prevent order failures. 

**2.4.2 Customers** : General mobile users who interact with the system occasionally or frequently browse catalogs, place orders, and track deliveries. They rely on the platform’s escrow mechanism to ensure their payments remain secure until delivery is verified. 

**2.4.3 Riders** : High-mobility delivery personnel who use their mobile devices to accept tasks and update delivery states to trigger fund releases. Their compensation is transparently calculated using a GPS-verified formula based on distance and waiting time. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 11_** 

**2.4.4 Platform Administrators** : Technical managers who use a specialized web dashboard to oversee governance, approve users, and configure policy rules. They are secondary users who primarily intervene to resolve complex disputes using uploaded evidence. 

#### **2.5 Operating Environment** 

The Vendra will run on different environments listed down in the table below: 

|**_Interface_**|**_OS / Environment_**|**_Language / Framework_**|
|---|---|---|
|**_Android_**|_5.0 and above_|_Java / React Native_|
|**_Website_**|_Modern Web Browser_|<br>_React_|
|**_Desktop (Admin)_**|_-_|_-_|



_Table 3.1 Operating Environment_ 

##### **2.5.1 Android view** 

Designed as a high-performance, mobile-first interface for Riders and Customers on the go. Optimized for quick touch interactions, barcode scanning, and real-time GPS tracking. 



<!-- Start of picture text -->
Vendra &<br>Pakistan's Leading Marketplace<br>Customer Vendor Rider<br>Welcome Back<br>Phone Number or Email<br>a<br>Password Forgot?<br>lctetae renee INS<br>>=<br>Gc if<br>Don't have an account? Sign up now<br><!-- End of picture text -->



<!-- Start of picture text -->
€ Product Details < 9<br>/<br>b=]<br>VEADRA<br>Saari<br>-<br>3 Sold by j Fresh Mart a<br>Organic Basmati Rice Skg<br>Yr 4.3» 128 Reviews - 2.1k Sold<br>RS.1,250 3500 nore<br>PaymentEscrow  secured by Vendra<br>Funds are held until you confirm<br>delivery.<br>Hindlinbte Stock ania<br>tate<br><!-- End of picture text -->

_Figure 2.2 – Login Mobile_ 

_Figure 2.3 – Product Detail Mobile_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 12_** 



<!-- Start of picture text -->
= Vendra of<br>© Delivering to: Gulshan Iqbal, Lahore<br>Q Search forA groceries, clothing. ov<br>Free Delivery!<br>Code: VENDRAI<br>Categories<br>=<br>ea= @ &st<br>Groceries Clothing Food Electronics<br>Nearby Stores, See All<br>: r]<br>= =<br>‘Al-Fatah Superm... (#48)  Savour Foods<br>Groceries + 1.2 km Pakistani «2.5 km<br>© 6-20mne © 90-40mine<br>Today's Picks<br>p =<br>a<br>TapalTea 800g Danedar Black NationalKetchup Tomato800g<br>Re 1480 @ wit @<br>oe iis =<br>Premium Basmati Rice Dalida Cooking Oil<br>5kg<br>Pouch1L<br>poe @ ssc @<br>Q 5 9g &<br>Explore Orders. «Saved ——Profile<br><!-- End of picture text -->



<!-- Start of picture text -->
€ Report an Issue<br>(2) Payment Securely Held<br>Your Rs.2,500 is safe in escrow until<br>this dispute is resolved.<br>Order Details,<br>Fresh Mart Gujranwala<br>Super Kernel Basmati Rice<br>5k°<br>Qty: 2 * Order #PK-84729<br>Step 1 of 2 Issue Details<br>—_——_<br>g e<br>Not Received Wrong Item<br>,<br>a ¥<br>Damaged Missing Parts<br>Describe the issue<br>E.g., | ordered Super Kernel Basmati but<br>received regularmariaelbroken rice insteasou<br>Attach Evidence (Optional)<br>Gonna ><br><!-- End of picture text -->

_Figure 2.5 – Dispute Submission Mobile_ 

_Figure 2.4 - Customer Homepage Mobile_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 13_** 



<!-- Start of picture text -->
€ Track Order Help?<br>Order Number © outfor Delivery<br>Estimated Delivery<br>Today by 5:30 PM<br>Secure<br>a) Funds areEscrowheld  Paymentsecurely untilRs.you2,500<br>confirm delivery.<br>—_————<br>@ rer confirmed<br>Today, 10:30 AM<br>Prepared & Packed<br>(v)<br>Today, 2:15 PM<br>Out for Delivery<br>fe}<br>Rider is on the way y to toy your location.<br>Delivered<br>Pending confirmation<br>Ali Hassan ©<br>*<br>Order Summary View Details<br>2x Premium Organic Basmati Rice RS: 2,400<br>(Skg)<br>1 Delivery Fee Rs. 180<br>Total Payment Rs. 2,580<br>u<br><!-- End of picture text -->



<!-- Start of picture text -->
GoodPlatinumafternoon,Rider Ali ¢,-<br>O@iD offline<br>TODAY'S EARNINGS Details ><br>rs. 850<br>6Deliveries @ 32hOnline Time<br>New Delivery Request<br>© Pickup<br>Al-Fatah Supermarket<br>DHA Phase 5, Lahore + 1.2 km away<br>(J DROP-OFF<br>Askari 11, Sector B<br>Est. 15 mins « 4.5 km total trip<br>Estimatedir Payoutut poms<br>Rs. 240 © Cash on Delivery<br>Decline © Accept Request<br>gm Fresh Mart Grocery<br>Picking up 4 items<br>A Navigate Xe<br>Q fu] a<br>Explore Cart Orders Profile<br><!-- End of picture text -->

_Figure 2.7 – Rider Home Mobile_ 

_Figure 2.6 – Order Tracking Mobile_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 14_** 

##### **2.5.2 Tablet View** 

Specifically tailored for the **Vendor POS** , providing a larger workspace for inventory management. Enables side-by-side views of active orders and real-time stock levels for faster in-store processing. Features an intuitive layout that bridges the gap between physical retail and digital storefronts. 



<!-- Start of picture text -->
Fresh Mart<br>— POS Mode & pnmas carrie) ==<br>Q ™ Current Sale a<br>C td) e<br>ha fel<br>° e<br>Total Rs. 990<br>a<br><!-- End of picture text -->

_Figure 2.8 – POS Screen Tablet_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 15_** 

##### **2.5.3 Web Browser View** 

A comprehensive, full-scale dashboard designed for the **System Admin** and deep data analysis. Provides complex data visualization for the Policy Engine, user management, and financial auditing. Optimized for desktop browsers to ensure maximum control over the entire marketplace ecosystem. 



<!-- Start of picture text -->
Vendra Platform Overview A ssmvaiuse f ©<br>seen we ndnrs € ontnemans yy rss Touny | Ovenonnaes & | pentng og<br>148 34 1,284 5 8<br>sas contomere Daily Orders & Revenue verranm Pending Approvals<br>Platform Health<br>Recent Disputes Vw A> symm me sss0n<br><!-- End of picture text -->

_Figure 2.9 – Admin Dashboard Web_ 

**_Page 16_** 

**_Software Requirements Specification & Design Description for Vendra_** 



<!-- Start of picture text -->
FB Vendra —Pavistanka Digital Bazaar Q | @ianore categories desis sot tp «HOD Login | Sign Up<br>Gea<br>Apni Pasand, Apki Dukan<br>Vendra<br><!-- End of picture text -->

_Figure 2.10 – Customer Homepage Web_ 



<!-- Start of picture text -->
Ow Good morning, Ahmad og<br>ee 24 Rs.18,400 6 5<br>EB orders@<br>Ace Live Orders View Alt Quick Actions<br>© Pajoun Ce co r=) S<br>, s a 2<br>Revenue Overview oe Wom<br>4 Restock Alerts<br>® Settings<br><!-- End of picture text -->

_Figure 2.11 – Vendor Dashboard Web_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 17_** 

## **<mark>3 Specific Requirements</mark>** 

#### **3.1 Functional Requirements** 

These requirements determine exactly what the system will do, how it will manage inventory synchronization between the shop and the marketplace, and the specific workflows for ensuring payment security and delivery accountability. 

|**ID**|**FR 01**|
|---|---|
|**Title**|Dual InventorySynchronization|
|**Description**|Maintaining two concurrent stock values for every product: Private (actual<br>physical units)and Public(visible onlinequantity).|
|**Actors**|Vendor,System|
|**Initial status an**|**dpreconditions**|
|**-**|The vendor must be registered and authenticated.|
|**-**|Product catalogmust be initialized in the database.|
|**Basic flow**||
|**-**|Vendor adds stock via mobile camera barcode scanning.|
|**-**|System calculates Public Stock by subtracting a policy-driven buffer from<br>Private Stock.|
|**Risk**||
|**-**|Network failure leads to delayed synchronization between shop and<br>marketplaces.|
||_Table 3.2 FR 01 – Dual Inventory Synchronization_|



**_Page 18_** 

**_Software Requirements Specification & Design Description for Vendra_** 

|**ID**|**FR 02**|
|---|---|
|**Title**|Real-time Order Reservation|
|**Description**|Automatically "locking" inventory items in the vendor’s POS when a<br>customerplaces an online order.|
|**Actors**|Customer,Vendor,System|
|**Initial status an**|**dpreconditions**|
|**-**|Customer has items in the mobile cart and initiates checkout.|
|**-**|Items must have sufficient Public Stock available.|
|**Basic flow**||
|**-**|System creates temporaryreservations for specific units.|
|**-**|POS interface on vendor phone reflects "Reserved" status for walk-in<br>cashiers.|
|**Risk**||
|**-**|Concurrent walk-in sale and online order at the exact same millisecond<br>(race condition).|
||_Table 3.3 FR 02 – Real-time Order Reservation_|



|**ID**|**FR 03**|
|---|---|
|**Title**|Escrow Fund Management|
|**Description**|Holding customer funds securely until delivery verification is completed<br>bythe rider.|
|**Actors**|Customer,Rider,System|
|**Initial status an**|**dpreconditions**|
|**-**|Customer completes a successful digitalpayment transaction.|
|**Basic flow**||
|**-**|Funds are moved to a "Held in Escrow" state in the database.|
|**-**|System releases funds to vendor wallet only upon Rider marking<br>"Delivered" on mobile.|
|**Risk**||
|**-**|Dishonest Rider markingdeliverywithoutphysical handover.|



_Table 3.4 FR 03 – Escrow Fund Management_ 

**_Page 19_** 

**_Software Requirements Specification & Design Description for Vendra_** 

|**ID**|**FR 04**|
|---|---|
|**Title**|GPS-Based Rider Payout|
|**Description**|Calculating rider earnings based on verified distance and waiting time<br>rules.|
|**Actors**|Rider,System|
|**Initial status an**|**dpreconditions**|
|**-**|Rider must have location services(GPS)active on their mobile device.|
|**Basic flow**||
|**-**|System tracks GPS coordinates frompickupto deliverylocation.|
|**Risk**||
|**-**|GPS signal loss in high-density urban areas resulting in incorrect distance<br>calculation.|
||_Table 3.5 FR 04 – GPS-Based Rider Payout_|



|**ID**|**FR 05**|
|---|---|
|**Title**|Secure Role-Based Login|
|**Description**|Providing distinct, secure access for Admin, Vendor, Rider, and<br>Customer roles via JWT sessions.|
|**Actors**|All Users|
|**Initial**<br>**status**|Users must have the mobile app or access the web dashboard.|
|**Basic flow**|System validates credentials and grants access only to the user's assigned<br>role-specific dashboard.|
|**Risk**|Unauthorized access if session tokens are compromised.|
||_Table 3.6 FR 05 – Secure Role-Based Login_|



|**ID**|**FR 06**|
|---|---|
|**Title**|Product CatalogManagement|
|**Description**|Allowing vendors to add, update, and manage products, pricing, and<br>categories on theplatform.|
|**Actors**|Vendor,Admin|
|**Basic flow**|Vendor inputs product details and prices; Admin approves the catalog for<br>marketplace visibility.|
||_Table 3.7 FR 06 – Product Catalog Management_|



**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 20_** 

|**ID**|**FR 07**|
|---|---|
|**Title**|Pick-Pack-ReadyWorkflow|
|**Description**|Structured staff workflow for picking items and marking orders ready for<br>riderpickup.|
|**Actors**|Vendor(Staff)|
|**Basic flow**|Staff views "Reserved" orders, picks items, packs them, and updates the<br>state to "Readyfor Pickup".|
||_Table 3.8 FR 07 – Pick-Pack-Ready Workflow_|



|**ID**|**FR 08**|
|---|---|
|**Title**|Policy-Based Dispute Resolution|
|**Description**|Resolving conflicts between users based on uploaded evidence and pre-<br>definedplatform rules.|
|**Actors**|Admin,Customer,Vendor,Rider|
|**Basic flow**|User uploads photos/timestamps; Admin reviews evidence against policy<br>to decide fund release or refund.|
||_Table 3.9 FR 08 – Policy-Based Dispute Resolution_|



|**ID**|**FR 09**|
|---|---|
|**Title**|Real-time Order Notifications|
|**Description**|Automated alerts for order status changes and deliverytask assignments.|
|**Actors**|All Users|
|**Basic flow**|System triggers SMS or in-app notifications whenever an order moves to|
||a new lifecycle state.|



_Table 3.10 FR 09 – Real-time Order Notifications_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 21_** 

## **<mark>4 Other Non-functional Requirements</mark>** 

#### **4.1 Performance Requirements** 

These requirements define the speed, efficiency, and scalability standards. **Vendra** must maintain to ensure a reliable user experience across the mobile ecosystem. Given the real-time nature of inventory synchronization, these metrics are critical to preventing "double-selling" and maintaining trust. 

|**ID**|**PR 01**|
|---|---|
|**Title**|Real-Time InventorySynchronization|
|**Priority**|1(Critical)|
|**Description**|Any stock change made at the Vendor POS must reflect in the Customer<br>marketplace within**3-5 seconds**.|
|**Rationale**|This prevents "phantom stock" failures where a walk-in customer buys<br>the last item while it still appears available online.|
||_Table 4.1 PR 01 – Real-Time Inventory Synchronization_|



|**ID**|**PR 02**|
|---|---|
|**Title**|Order Reservation Latency|
|**Priority**|1(Critical)|
|**Description**|The transition from "Checkout initiated" to "Stock Reserved" must be<br>processed in under**2 seconds**.|
|**Rationale**|Fast reservation ensures transactional consistency and prevents two<br>customers from lockingthe same limited item simultaneously.|
||_Table 4.2 PR 02 – Order Reservation Latency_|



|**ID**|**PR 03**|
|---|---|
|**Title**|GPS TrackingFrequency|
|**Priority**|2(High)|
|**Description**|Rider location coordinates must be transmitted to the server every**10**<br>**seconds**duringan active task.|
|**Rationale**|Frequent updates are required for accurate "Distance" and "Wait Time"<br>payout calculations,as well as live order trackingfor the customer.|
||_Table 4.3 PR 03 – GPS Tracking and Update Frequency_|



**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 22_** 

|**ID**|**PR 04**|
|---|---|
|**Title**|Database Transaction Concurrency|
|**Priority**|1(Critical)|
|**Description**|The system must support at least**100 concurrent inventory requests**per<br>second without stock ledger corruption.|
|**Rationale**|Essential for a multi-vendor environment where thousands of customers<br>and vendors maybeperformingactions atpeak times.|
||_Table 4.4 PR 04 – Database Transaction Concurrency_|



|**ID**|**PR 05**|
|---|---|
|**Title**|Mobile Application Load Time|
|**Priority**|2(High)|
|**Description**|The initial application splash screen to functional dashboard transition<br>must not exceed**5 seconds**on a standard 4G connection.|
|**Rationale**|High-speed load times improve user retention and ensure vendors can<br>process walk-in customers without significant delays.|
||_Table 4.5 PR 05 – Application Load and Response Time_|



|**ID**|**PR 06**|
|---|---|
|**Title**|Financial Calculation Accuracy|
|**Priority**|1(Critical)|
|**Description**|Rider payouts and Escrow releases must be calculated to the**nearest 0.01**<br>**currency unit**with zero roundingerrors.|
|**Rationale**|Precise calculations are necessary to maintain trust with vendors and<br>riders,ensuringall commissions and fees align with theplatformpolicy.|



_Table 4.6 PR 06 – Payout Calculation Integrity_ 

#### **4.2 Safety and Security Requirements** 

This section specifies the safeguards necessary to prevent financial loss, data breaches, and operational harm. The system is expected to maintain a high level of security to ensure that transactions between customers, vendors, and riders remain transparent and protected. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 23_** 

|**ID**|**SSR 01**|
|---|---|
|**Title**|Authentication and Access Security|
|**Priority**|1(Critical)|
|**Description**|All mobile and web sessions must be secured using JSON Web Tokens|
||(JWT)and Role-Based Access Control(RBAC).|
|**Rationale**|Ensures that riders cannot access vendor pricing and customers cannot<br>viewprivate shopdata.|
|**Action**|Encrypt allpasswords and session tokens in the database .|



_Table 4.7 SSR 01 – Authentication and Access Security_ 

|**ID**|**SSR 02**|
|---|---|
|**Title**|Escrow Financial Safety|
|**Priority**|1(Critical)|
|**Description**|Funds must be held in a secure, immutable state until verified delivery<br>occurs.|
|**Rationale**|Prevents fraudulent direct payments and ensures customer trust by only<br>releasingfunds uponphysical verification.|
|**Action**|Require the Rider app to verify GPS coordinates at the point of delivery<br>before fund release.|



_Table 4.8 SSR 02 – Escrow Financial Safety_ 

|**ID**|**SSR 03**|
|---|---|
|**Title**|Data Integrityand Privacy|
|**Priority**|1(Critical)|
|**Description**|The system must not store or transmit confidential personnel info that<br>violates localprivacylaws.|
|**Rationale**|Protects the system against legislative issues and maintains the<br>confidentialityof allpersonnel involved.|
|**Action**|Log all state changes in an immutable stock ledger to prevent manual<br>inventorytampering.|



_Table 4.9 SSR 03 – Data Integrity and Privacy_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 24_** 

|**ID**|**SSR 04**|
|---|---|
|**Title**|Operational Safety (Buffer Stock)|
|**Priority**|2(High)|
|**Description**|Enforcement of a "Public Stock" limit that is lower than actual physical<br>inventory.|
|**Rationale**|Safeguards the vendor against accidental overselling to walk-in<br>customers when online orders are inprogress.|
|**Action**|Automatically deduct items from public visibility the moment an online<br>checkout starts.|



_Table 4.10 SSR 04 – Operational Safety (Buffer Stock)_ 

#### **4.3 Software Quality Attributes** 

##### **4.3.1 Reliability** 

The system is required to maintain a target of 99.9% uptime for core transactional services, specifically focusing on the consistency of inventory and financial data. To achieve this, we will implement automated database transactions and atomic state-locking mechanisms to ensure that inventory counts, and escrow states are never corrupted during high-concurrency periods. Reliability will be verified through stress-testing with simulated concurrent walk-in and online orders to confirm that stock ledgers remain accurate under heavy load. 

##### **4.3.2 Availability** 

Vendra’s primary marketplace and POS functions must remain accessible on mobile devices and the administrative web dashboard during standard operational hours. This will be achieved by utilizing a lightweight Node.js backend hosted in a cloud environment that features automatic failover capabilities. Verification will involve periodic health checks to monitor server response times and database connectivity, ensuring that vendors and customers experience minimal downtime. 

##### **4.3.3 Maintainability (Design for Change)** 

The platform’s code must be structured modularly to allow for future extensions, such as new payment methods or third-party logistics, without requiring complete architectural rewrite . Our strategy involves adhering to Software Design and Architecture (SDA) principles, utilizing decoupled Node.js services and a centralized Policy Engine that allows business rules to be updated via the database rather than code redeployment. We will verify this attribute through code reviews and by testing the dynamic adjustment of policy variables independent of the core logic. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 25_** 

##### **4.3.4 Usability (User-Friendliness)** 

The mobile interface is designed to be simple enough for a vendor to complete a barcode-scan sale in under 10 seconds, even with minimal technical training. To achieve this, we will prioritize ease of use over ease of learning by implementing a high-contrast, button-heavy UI optimized for fast-paced retail environments. Usability will be verified through field testing with local shopkeepers to measure the efficiency of order packing and inventory updates. 

##### **4.3.5 Robustness** 

The system must be capable of handling unexpected errors, such as temporary network drops or invalid user inputs, without crashing or losing critical transactional data. This robustness will be built using strict client-side validation on mobile apps and thorough server-side verification for every API call to prevent data corruption. Verification will include fault-injection testing, such as intentionally disconnecting the network during a checkout, to confirm that the system recovers gracefully without duplicating or losing orders. 

##### **4.3.6 Portability** 

While the current implementation focuses on mobile interfaces and web-based administration, the underlying infrastructure must remain platform-agnostic to facilitate future expansion. By utilizing a standardized React and Node.js tech stack, we ensure the system can be migrated between different cloud providers or extended to other operating systems with minimal modification. Verification will involve testing the backend on both Windows and Linux-based environments to ensure total cross-platform compatibility. 

**_Page 26_** 

**_Software Requirements Specification & Design Description for Vendra_** 

## **<mark>5 Design Description</mark>** 

#### **5.1 Composite Viewpoint** 

The Composite Viewpoint defines the high-level organizational structure of the **Vendra** system. It identifies the major design constituents and how they are assembled into a cohesive, modular architecture. By separating the system into logical packages, we ensure that the user interface, business logic, and data storage layers remain decoupled, allowing for easier maintenance and scalability. 

##### **5.1.1 Package Diagram (Logical)** 

The following package diagram explains how the system will work and provides a clear view of the hierarchical structure of the various UML elements. It gives an overview of how the attributes in a package are connected between one element and another. 



<!-- Start of picture text -->
Package: UI<br>Vendor POS Page Customer Page Rider Page Admin Web Dashboard<br>v<br>Package: Controller<br>‘Auth Manager ————— Order Lifecycle ————— __ EscrowHandler ———_ Policy Manager<br>v<br>Package: Model<br>User Profile “ew Record/Ledger —<br>“4<br>” Database<br>Model Logic ==="<br><!-- End of picture text -->

_<mark>Figure 5.1: Package Diagram for Vendra showing UI, Controller, and Model Layers</mark>_ 

##### **5.1.2 Logical Dependencies** 

The system follows a strict hierarchical dependency flow. The **UI Package** interacts solely with the **Controller Package** to trigger operations, ensuring no direct unauthorized access to the database. The **Controller Package** validates requests against the **Policy Manager** before committing changes to the **Model Package** . This modular assembly ensures that the **Escrow Handler** and **Inventory Ledger** maintain transactional integrity across the entire marketplace ecosystem. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 27_** 

#### **5.2 Logical Viewpoint** 

The Logical Viewpoint elaborates on the system's static structure by defining the core classes, their attributes, methods, and the relationships between them. It serves as a blueprint for the implementation phase, ensuring that business logic such as dual-inventory management and escrow security is structurally sound. 

##### **5.2.1 Class Diagram** 

The class diagram below illustrates the inheritance hierarchy and associations that govern the Vendra platform. It focuses on the interaction between the centralized **User** base and the transactional entities like **Order** , **Inventory** , and **Escrow** . 



<!-- Start of picture text -->
User<br>int usertD<br>+string email<br>+string role<br>+string jwtToken —<br>Custome<br>+placeOrder()<br>+trackDelivery()<br>+cancelOrder()<br>+ |<br>places<br>Order<br>+tint orderiD<br>| __ timestamp+string status createdAt<br>+updatestatus()<br>assigned fil AS<br>| 1<br>mA _t0 delivered_by secured_by<br>Vendo: a<br>+string storeLocation +float gpsLocation +float+stringheldAmountstatus<br>+updateStocksateen) +updateDeliveryState() +releaseToVendor()<br>+packOrder() +initiateRefund()<br>manages<br>Inventon<br>tint productiD<br>-int privateStock<br>+int publicStock<br>+lockQuantity()<br>+syncStock()<br><!-- End of picture text -->

_Figure 5.2: Complete Class Diagram for Vendra showing static relationships_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 28_** 

##### **5.2.2 Structural Relationships** 

- **Generalization:** The Vendor, Customer, and Rider classes inherit from the User class, promoting code reusability for identity-related attributes like jwtToken. 

- **Encapsulation:** The Inventory class specifically marks privateStock as a private member (-), ensuring that physical stock levels can only be modified through controlled methods like syncStock(). 

- **Associations:** Multiplicity is enforced to ensure data integrity; for example, a single Customer can place multiple orders (1 to *), but each Order is secured by exactly one Escrow instance (1 to 1). 

#### **5.3 Information Viewpoint** 

The Information Viewpoint is essential for systems like **Vendra** that require substantial persistent data storage to maintain transactional integrity. This viewpoint defines the data structures and the logical relationships between them, ensuring that information such as inventory levels and escrow balances remains consistent across the database. 

##### **5.3.1 Entity Relationship Diagram (ERD)** 

The following ERD explains how the entities relate to each other within the system. Concepts such as Users, Products, and Orders are stored as entities, each with specific attributes. These entities are linked through diamond-shaped relationship connectors that define the business rules of the platform. 



<!-- Start of picture text -->
eice<br>ofiin<br><!-- End of picture text -->

_Figure 5.3: ERD for Vendra showing transactional relationships and attributes_ 

**_Page 29_** 

**_Software Requirements Specification & Design Description for Vendra_** 

##### **5.3.2 Cardinality and Data Rules** 

- **One-to-Many (1:N):** A single User (Customer) can place multiple orders over time, but each Order is uniquely associated with the user who initiated it. 

- **Many-to-Many (N:M):** An Order can contain multiple products, and a single Product can be part of many different orders, necessitating a robust mapping in the database. 

- **Dual Inventory Storage:** By storing private_stock and public_stock within the Product entity, the system ensures that physical shelf counts and digital marketplace availability are always linked at the database level. 

#### **5.4 Interaction Viewpoint** 

The Interaction Viewpoint defines the dynamic behavior of the system by illustrating how objects and actors collaborate over time to achieve specific functionalities. It focuses on the exchange of messages, concurrent tasks, and asynchronous triggers required to maintain system-wide synchronization between the marketplace and physical inventory. 

##### **5.4.1 Sequence Diagram: End-to-End Order Fulfillment** 

The following sequence diagram captures the primary use-case of the **Vendra** system: from the initial customer checkout to the final financial settlement. It highlights the critical handshake between the inventory database, escrow handler, and the mobile applications for vendors and riders. 



<!-- Start of picture text -->
Software Requirements Specification & Design Description for Vendra  Page 30<br>Ror<br>Customer ‘Customer Ape Nodes Backend ventory 08, Escrow Handtor ‘vendor POS Riaor App<br>Phase 1: Onder Reservation<br>Initos Checkout<br>POST /apvordorsichockout<br>check Putie Stock Avaabaty<br>a [Stock Avaliaie}<br>Stock vais<br>Lock Quantity (Reserve)<br>le. Escrow State = Pending<br>Push Notitcation (New Order Reserved)<br>Phase 2: Fulftlment & Delvry<br>Pack Ordor<br>_—<br>Mark a6 “Ready for Pickup”<br>Broadcast Deivary Task<br>Acca Task<br>Update Status: “On the Way"<br>Phase 3: Completion& Setloment<br>Handover tame<br>Contm Delivery (GPS Vere)<br>POST laplidetveryicomplte<br>Credit Rider Payout<br>Notly Customer: Delivered<br>[Stock Unavatabie]<br>Error: tem Sold Out<br>Rider<br>Cumtomer Customer Ape Node je Backend Inventory 08 Escrow Handior ‘Vendor POS Rider Ave<br><!-- End of picture text -->

_Figure 5.4: Sequence Diagram for Vendra showing the three phases of order fulfillment_ 

##### **5.4.2 Behavioral Phases** 

The interaction logic is divided into three distinct operational phases to ensure transactional integrity: 

- **Phase 1: Order Reservation:** Upon checkout, the **Node.js Backend** performs a synchronous check with the **Inventory DB** . If stock is valid, it immediately executes a "Lock Quantity" command and moves the **Escrow Handler** to a "Pending" state, preventing any physical or digital overselling during the process. 

- **Phase 2: Fulfillment & Delivery:** This phase demonstrates asynchronous messaging where the **Vendor POS** triggers a broadcast to the **Rider App** . The interaction remains in a transit state until the Rider accepts the task and physically picks up the items. 

- **Phase 3: Completion & Settlement:** The final interaction is triggered by a **GPS-verified confirmation** from the Rider. Only after this verification does the backend instruct the **Escrow Handler** to release funds to the Vendor and credit the Rider’s payout, closing the communication loop securely. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 31_** 

#### **5.5 State Dynamics Viewpoint** 

The State Dynamic Viewpoint expresses the dynamic state transformations of the system under study. This viewpoint is critical for **Vendra** as it captures how concurrent entities specifically the Order, the Inventory, and the Escrow funds change their status in response to real-world events and system triggers. 

##### **5.5.1 State Machine Diagram** 

The following state machine diagram illustrates the parallel lifecycles within the Vendra System. It highlights how a single customer action (Checkout) initiates synchronized transitions across three distinct functional regions: Order Fulfillment, Inventory Status, and Escrow & Financials. 



<!-- Start of picture text -->
I<br>Vendra_System<br><!-- End of picture text -->

_Figure 5.5: Concurrent State Machine Diagram for Vendra_ 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 32_** 

##### **5.5.2 State Transition Analysis** 

The system logic is designed to ensure that no state transition occurs in isolation. The synchronization of these states maintains the integrity of the "Dual Inventory" and "Escrow" requirements: 

- **Order Fulfillment:** Captures the physical journey of the goods. Transitions such as Picked to OnTheWay are dependent on external triggers like barcode scanning and GPS verification. 

- **Inventory Status:** Manages the availability of items. When an order is Reserved, the inventory enters a Reserved Lock state, ensuring the physical item in the POS cannot be sold to a walk-in customer. Permanent deduction only occurs upon successful delivery. 

- **Escrow & Financials:** Governs the safety of funds. Funds move from PaymentPending to FundsHeld immediately upon checkout. The transition to FundsReleased is strictly gated by the Order state reaching Delivered. 

#### **5.6 Algorithm Viewpoint** 

The Algorithm Viewpoint provides the detailed operational logic for the system's core functions. It defines the procedural steps required to maintain the "Vendra" ecosystem's integrity, focusing on the complex interplay between inventory synchronization, delivery verification, and financial settlement. 

##### **5.6.1 System Pseudo-Code** 

The pseudo-code below represents the high-level design of the complete software logic. It ensures that critical business rules such as geofencing for deliveries and atomic transactions for payments are enforced at the functional level. 

**_Software Requirements Specification & Design Description for Vendra_** 

**_Page 33_** 



<!-- Start of picture text -->
5.6 Algorithm Viewpoint. System Pseudo-Code<br>ALGORITHM<br>Vendra_Order_Lifecycle(CustomerID,<br>VendorID, CartItems)<br>BEGIN<br>// PHASE 1: PRE-CHECK & INVENTORY<br>LOCKING<br>FOR EACH item IN CartItems DO<br>IF (item.qty > item.PublicStock)<br>THEN<br>SIGNAL ‘Insufficient Stock’ &<br>‘TERMINATE<br>END IF<br>END FOR<br>INITIATE ATOMIC_TRANSACTION<br>Inventory. Lock(CartItems,<br>Privatestock)<br>Inventory.Hide(CartItems,<br>PublicStock)<br>Escrow.HoldFunds<br>Order .SetStatus('Reserved")(Order. TotalAmount)<br>COMMIT ATOMIC_TRANSACTION<br>// PHASE 2: FULFILLMENT & RIDER LOGIC<br>IF (Vendor.Marks_Packed) THEN<br>Order.SetStatus('Ready_for_Pickup")<br>Broadcast_Task_To_Riders(Radius =<br>5Skm)<br>END IF<br>IF (Rider.Arrives_at_Destination)<br>THEN<br>IF (Distance(Rider.GPs,<br>Customer.GPS) <= 200m) THEN<br>Order .SetStatus( ‘Delivered’ )<br>CALL<br>Execute_Financial_Settlement()<br>ELSE<br>PROMPT ‘Invalid Delivery<br>Location’<br>END IF<br>END IF<br>END<br><!-- End of picture text -->

_Figure 5.6: Integrated System Pseudo-code for Order Lifecycle and Financial Settlement_ 

##### **5.6.2 Procedural Strategy** 

The system logic is built upon three primary design principles to ensure reliability: 

- **Atomic Transactions:** In **Phase 1** , the locking of physical inventory and the holding of escrow funds are treated as a single atomic unit. This prevents "phantom stock" issues by ensuring that inventory is never reserved unless payment is successfully initiated. 

- **Geofencing Verification:** The algorithm enforces security in **Phase 3** by utilizing a proximity check. The transition to a "Delivered" state and the subsequent release of funds is only possible if the Rider’s GPS coordinates are within 200 meters of the Customer's designated location. 

- **Policy-Driven Payouts:** The Execute_Financial_Settlement() method dynamically calculates payouts by fetching rates (Base, Distance, and Wait time) from a centralized Policy Engine, allowing for transparent and flexible financial management. 

