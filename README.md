# Vendra: Multi-Vendor Digital Marketplace 🏪🇵🇰

> Pakistan's Leading Multi-Vendor Marketplace — FYP 30% Implementation
> Dual Inventory Management + Atomic Order Reservation

---

## 📋 Project Overview

**Problem:** In Pakistan, physical shop stock and online stock are not synced, causing "phantom stock" order cancellations. Trust is low due to direct vendor payments.

**Solution (30% scope):** Dual Inventory (Private vs Public stock) + Real-time Atomic Order Reservation. Customer places orders, vendor manages dual inventory and sees reservations.

### Key Formula
```
public_stock = private_stock - buffer - reserved_quantity
```

---

## 🛠 Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Mobile** | Flutter 3.22+ (Dart) | Cross-platform, BLoC architecture, barcode support |
| **Backend** | Node.js + Express | REST API, JWT auth, atomic transactions |
| **Database** | PostgreSQL 16 | MVCC for concurrency, ACID, CHECK constraints |
| **State** | flutter_bloc | Clean, scalable, testable |
| **HTTP** | Dio | Interceptors, error handling |
| **Auth Storage** | flutter_secure_storage | Encrypted JWT persistence |

---

## 📁 Project Structure

```
FYP Data/
├── backend/                      # Node.js Backend
│   ├── package.json
│   ├── .env                      # Environment variables
│   ├── .env.example
│   ├── init.sql                  # Database schema
│   └── src/
│       ├── server.js             # Express entry point
│       ├── db.js                 # PostgreSQL pool
│       ├── middleware/
│       │   └── auth.js           # JWT + Role middleware
│       ├── controllers/
│       │   ├── auth.controller.js
│       │   ├── vendor.controller.js
│       │   └── customer.controller.js
│       └── routes/
│           ├── auth.routes.js
│           ├── vendor.routes.js
│           └── customer.routes.js
│
└── vendra_app/                   # Flutter Mobile App
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── config/
        │   ├── app_theme.dart    # Colors, typography
        │   ├── app_routes.dart   # Named routes
        │   └── api_config.dart   # API endpoints
        ├── core/
        │   ├── models/           # Data models
        │   ├── services/         # API + Storage services
        │   └── widgets/          # Reusable UI components
        └── features/
            ├── auth/             # Login, Signup, Splash
            ├── customer/         # Home, Product Detail, Cart, Orders
            ├── vendor/           # Dashboard, Products, Orders, Ledger
            └── placeholder/      # Under Development screens
```

---

## 🚀 Setup Instructions

### Prerequisites
- **Node.js** v18+ ([nodejs.org](https://nodejs.org))
- **PostgreSQL** 16+ ([postgresql.org](https://postgresql.org))
- **Flutter** 3.22+ ([flutter.dev](https://flutter.dev))
- **Android Studio** with Android SDK configured
- **Android Emulator** or physical device

### 1. Database Setup

```bash
# Create the database
psql -U postgres
CREATE DATABASE vendra_db;
\q

# Run the schema
psql -U postgres -d vendra_db -f "d:/FYP Data/backend/init.sql"
```

### 2. Backend Setup

```bash
cd "d:/FYP Data/backend"

# Install dependencies
npm install

# Configure environment
# Edit .env file with your PostgreSQL password:
# DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/vendra_db
# JWT_SECRET=your_secret_key

# Start server
npm start
# or for development with auto-reload:
npm run dev
```

The API will be running at **http://localhost:3000**

Test: `curl http://localhost:3000/api/health`

### 3. Flutter App Setup

```bash
cd "d:/FYP Data/vendra_app"

# Create Flutter project scaffolding (platform files)
flutter create --project-name vendra_app .

# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run
```

### 4. Base URL Configuration

Edit `lib/config/api_config.dart`:
- **Android Emulator:** `http://10.0.2.2:3000` (default)
- **Physical Device:** `http://YOUR_PC_IP:3000` (find via `ipconfig`)
- **Same Machine:** `http://localhost:3000`

---

## 🧪 Testing the Full Flow

### Step 1: Create a Vendor Account
1. Open app → Login screen
2. Select **Vendor** tab
3. Tap **Sign up now**
4. Fill: Name, Store Name, Email, Password
5. You'll land on the **Vendor Dashboard**

### Step 2: Add Products
1. Tap **+ Add Product** FAB
2. Fill: Product Name, Price, Private Stock (e.g., 100), Buffer (e.g., 5)
3. Public Stock = 100 - 5 - 0 = **95** (visible to customers)
4. Tap **Add Product**

### Step 3: Create a Customer Account
1. Logout from vendor
2. Select **Customer** tab → Sign up
3. You'll land on **Customer Home**

### Step 4: Place an Order
1. Browse products → Tap a product → **Add to Cart**
2. Go to **Cart** (top-right icon)
3. Adjust quantity → **Place Order**
4. See **Order Confirmed** screen
5. Check: product's public stock is now reduced!

### Step 5: Verify on Vendor Side
1. Login as vendor
2. **Orders** tab → see the new order with "Confirmed" badge
3. **Home** tab → product shows updated reserved count
4. **Ledger** tab → see "Reserved" entry

---

## 📡 API Endpoints

### Auth
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/signup` | ❌ | Register (auto-creates vendor record if role=vendor) |
| POST | `/api/auth/login` | ❌ | Login → JWT token |
| GET | `/api/auth/me` | ✅ | Get current user profile |

### Products (Customer)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/products` | ❌ | Browse products (public_stock > 0) |

### Vendor
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/vendor/products` | ✅ Vendor | Create product |
| GET | `/api/vendor/products` | ✅ Vendor | List own products |
| PUT | `/api/vendor/products/:id` | ✅ Vendor | Update product |
| DELETE | `/api/vendor/products/:id` | ✅ Vendor | Soft-delete product |
| GET | `/api/vendor/orders` | ✅ Vendor | Get store orders |
| GET | `/api/vendor/inventory/ledger` | ✅ Vendor | Get inventory ledger |

### Customer
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/customer/checkout` | ✅ Customer | Atomic order reservation |
| GET | `/api/customer/orders` | ✅ Customer | Order history |

---

## 🎨 Design System

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#FF6B35` | Buttons, prices, accents |
| Secondary | `#004E89` | AppBar, links, vendor branding |
| Background | `#F5F5F5` | Page backgrounds |
| Success | `#28A745` | In-stock, confirmations |
| Error | `#DC3545` | Low-stock, errors |
| Reserved | `#F39C12` | Reserved stock badges |

Font: **Google Fonts Poppins** (all weights)

---

## 📌 30% Scope Coverage

| Requirement | Status |
|------------|--------|
| FR 05 – Role-Based Login | ✅ Implemented |
| FR 01 – Dual Inventory | ✅ Implemented |
| FR 02 – Atomic Order Reservation | ✅ Implemented |
| FR 06 – Product Catalog CRUD | ✅ Implemented |
| SSR 01 – JWT Auth + Secure Storage | ✅ Implemented |
| PR 02 – Real-time Stock Update | ✅ Implemented |
| PR 04 – MVCC Concurrency | ✅ PostgreSQL SELECT FOR UPDATE |
| Rider Module | 🚧 Placeholder |
| Escrow System | 🚧 Placeholder |
| Dispute Resolution | 🚧 Placeholder |
| Admin Dashboard | 🚧 Placeholder |
| GPS Tracking | 🚧 Placeholder |

---

## 👥 Team

Vendra — Final Year Project
