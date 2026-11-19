# Vendra live demo script

One order, end to end, in about 10 minutes. **Zohaib** drives the customer and admin screens, **Bilal** drives the vendor and rider screens.

## 30 minutes before (both)

- [ ] Laptop on charger, sleep and screen saver off, notifications muted (Focus Assist on).
- [ ] Internet / hotspot on. Map tiles and app fonts load online; everything else is local.
- [ ] Docker Desktop running, then from `C:\Projects\FYP`: `.\run-local.ps1`.
  Wait for the URL summary. Do **not** add `-Production`: the demo needs development mode.
- [ ] Check these all open:

  | Window | URL | Log in as |
  |---|---|---|
  | Customer app | http://localhost:5001 | `ahmed@customer.pk` |
  | Vendor app | http://localhost:5002 | `usman@vendor.pk` |
  | Rider app | http://localhost:5003 | `bilal@rider.pk` |
  | Admin dashboard | http://localhost:3001 | `admin@vendra.pk` |
  | Vendra Pay dashboard | http://localhost:4242 | (no login) |

  The password for every account is `password123`. Each login screen has a **demo quick-login** panel, so you can tap the account instead of typing.
- [ ] Use one Chrome window per app, sized like a phone (DevTools device mode, or a narrow window), arranged so you can Alt-Tab quickly. Hard refresh each once (Ctrl+Shift+R).
- [ ] Rider app: set the rider's location near **Blue Area** (the store) using *Simulate location*, then **Go online**.
- [ ] Customer app: make sure Ahmed's delivery pin is in **F-7** (the default demo account location).
- [ ] Admin → **Finance**: reconciliation shows **Balanced**. If not, do not demo the reconciliation step; use the backup slide.
- [ ] Vendor Usman's wallet has at least Rs 1,000 to withdraw. Seeded data usually gives plenty.

**Timers in development mode:** the store must accept within **5 min**, and a rider must claim a ready order within **10 min**, or the order auto-cancels and refunds. Escrow releases **2 min** after delivery.

## Test cards (any future expiry, any CVC)

| Card | Use it for |
|---|---|
| `4000 0027 6000 3184` | Checkout. Asks for the one-time password **123456**. |
| `4242 4242 4242 4242` | Withdrawals and quick payments. Succeeds immediately. |
| `4000 0000 0000 9995` | Show a decline (insufficient funds), if asked. |

---

## Step 1: Customer orders (Zohaib, about 2.5 min)

1. Customer app (Ahmed): open **Explore** and point at the store pins around Islamabad and Rawalpindi.
2. Open **Capital Electronics Hub** (Blue Area) and add 1–2 cheap items.
   > "Each store has its own cart, because every order goes from one shop with one rider."
3. Open the cart and choose **Home Delivery**. Point at **Delivery fee (x.x km)**.
   > "The server quotes this from the real distance: Rs 150 plus Rs 30 per km. Both are admin policies."
4. **Pay by card**: enter `4000 0027 6000 3184`, then the one-time password `123456`.
5. The order shows **Pending**.
   > "The money has left Ahmed's card and is now held in escrow. The vendor can't touch it yet."
6. *(Optional)* Switch to the Vendra Pay dashboard and show the payment that just succeeded.

## Step 2: Store prepares (Bilal, about 2 min)

1. Vendor app (Usman): the new order appeared without a refresh.
2. **Accept**, then **Mark as Packed**, then **Mark as Ready for Pickup**.
   > "Its units were reserved the moment Ahmed paid, so the counter can't sell them."
3. *(Optional, good for FR01)*: open **POS**, then **New sale**, sell one unit of a different product and **Complete sale**. On the customer app, that product's stock drops within a second.

## Step 3: Rider delivers (Bilal, about 3 min)

1. Rider app: the request appears under **Delivery requests** with its estimated payout. Tap **Accept**.
2. Use **Simulate drive** to reach the store, then tap **Arrived at store** and **Picked up**. Both are refused unless the rider is within 200 m of the store (pickup geofence).
3. Tap **Confirm delivery** now. It is **refused**: you are not within 200 m of the customer.
   > "This is our answer to a dishonest rider: the server checks the GPS against the customer's pin."
4. Use **Simulate drive**. The rider moves along the route; on the customer app the rider moves on the map.
5. On arrival, tap **Confirm delivery**. Show the payout figure (base + per km + waiting).

## Step 4: Money settles (Zohaib, about 2.5 min)

1. Admin → **Orders**: the order is **Delivered**, with escrow **held**.
   > "The vendor is paid only after the dispute window: 24 hours normally, 2 minutes in demo mode."
2. **While waiting**, Bilal talks through the *Testing* slide (about 2 min).
3. Admin → **Finance**: escrow released. Usman's share is the subtotal minus 10%; the platform keeps the commission plus the delivery margin.
4. Vendor app → **Wallet** → **Withdraw** Rs 1,000 to card `4242 4242 4242 4242`. The status shows **In transit** and turns **Paid** after about 20 s. Show it on the Vendra Pay dashboard.
5. Admin → **Finance**: reconciliation shows **Balanced**.
   > "Everything the gateway holds equals everything we owe, down to the paisa."

---

## If something goes wrong

| Problem | Do this |
|---|---|
| A page is blank or stuck | Hard refresh (Ctrl+Shift+R). If still stuck, switch to the backup slides. |
| The order auto-cancelled (store took over 5 min) | Say *"and that is our timeout protection, the customer is refunded"*. Show Ahmed's wallet, then place a new order. |
| "You are … m from the store" | The rider must be at the store first. Simulate the drive to the store, then try again. |
| No delivery request in the rider app | Check the rider is **online** and near the store (simulate location to Blue Area). |
| The map is grey | No internet. Carry on; everything except tiles works offline. |
| Backend not responding | Run `.\run-local.ps1` again (about 30 s), or switch to the backup slides. |
| Anything else | Go to the **Backup** slides (19–21) and narrate the same four steps. |
