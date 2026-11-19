# Vendra: likely examiner questions

Short answers first; the detail is there if they push. **[B]** = Bilal answers, **[Z]** = Zohaib answers.

## Inventory and orders

**1. What if a walk-in customer and an online customer buy the last unit at the same moment? [B/Z]**
Both requests must lock the same product row (`SELECT … FOR UPDATE`) inside one transaction. The second waits, then sees the updated stock and is refused with "insufficient stock". Our test fires 25 simultaneous checkouts at 13 units: exactly 13 succeed, every run.

**2. How is public stock calculated? [B]**
`public = max(0, private − buffer − reserved)`. The buffer is an admin policy (default 5) that the vendor can override per product. It is recomputed on the server in the same transaction as every stock change, so it is never stale.

**3. What is the inventory ledger for? [B]**
It is an audit trail: every stock in, sale, reservation and release is a row, so you can explain any stock number. This is the SRDS's "real-time stock ledger".

**4. What happens if the vendor never accepts, or no rider takes the order? [B]**
A background sweep runs every 30 s and cancels the order: after 30 min if the store hasn't accepted, after 60 min if no rider has claimed a ready order. It refunds the customer from escrow and releases the reserved stock. Both limits are admin policies.

## Riders and GPS

**5. How do you stop a rider faking delivery? [B]**
The server refuses "Delivered" unless the rider's reported GPS is within 200 m (a policy) of the customer's pin. "Arrived at store" and "Picked up" are checked the same way against the store (pickup geofence, also 200 m), so waiting-time pay can't be faked either. A store can't move its pin to get around this: once approved, a location change waits for the admin. The customer also has a dispute window before the vendor is paid.
In production mode, manually set locations are rejected by the server.
*Honest limit:* a rooted phone can spoof GPS. Fixing that needs OTP-at-door or a photo of the handover, which is future work.

**6. How is the rider paid? [B]**
`60 + 25 × km + 3 × (waiting minutes beyond 5)`. The km come from the GPS pings sent every 10 s, summed along the route. If there are fewer than two pings, it falls back to the straight-line distance, so the rider is never paid zero. All the numbers are admin policies.

**7. What if two riders accept the same task? [B]**
The accept is one `UPDATE … WHERE rider_user_id IS NULL` with a row lock. Exactly one wins; the other gets "already taken". This is covered by a test.

## Money

**8. Is the payment real? [Z]**
The money movement is real and fully accounted for, but the cards are test cards. Vendra Pay is our own gateway service, built like Stripe: tokens, payment intents, one-time password, payouts and signed webhooks.
Going live means swapping `gateway.client.js` for a real provider (PayFast, Stripe). The rest of the backend doesn't change.

**9. Why not use Stripe or JazzCash directly? [Z]**
They need a registered business and real KYC, which a student project can't get. We wanted real escrow, not a `paid = true` flag, so we built a gateway with the same API shape.

**10. Where exactly is the money while it is "in escrow"? [Z]**
In the `platform_escrow_wallet` row, not in the vendor's wallet. Every movement is an append-only `wallet_ledger` row with a reference. Release is done only by the server's sweep after the dispute window, never by a user tap.

**11. How do you know you haven't lost or created money? [Z]**
Reconciliation: the gateway's balance must equal all wallets + escrow + platform earnings + withdrawals in transit. It is checked in the admin finance page and after every money test. It caught a real bug for us (a withdrawal refunded after the payout had already gone).

**12. Why store money as integers? [Z]**
Floating point can't represent 0.1 exactly, so sums drift. We store whole paisa (Rs 1 = 100), which gives exact results and meets PR06 (accuracy to 0.01).

**13. What stops the same payment being charged twice? [Z]**
Idempotency keys on every gateway call. Webhooks are signed with HMAC-SHA256 and timestamped (5-minute tolerance), and each event is processed once.

## Security and architecture

**14. How is access controlled? [Z]**
- JWT on login; passwords stored as bcrypt hashes.
- Role middleware on every route.
- Every query is scoped to the owner: a vendor can only read their own orders.
- Production mode refuses to start with a weak JWT secret or without an allowed-origins list.

**15. Why Flutter instead of React Native (the SRDS said React Native)? [Z/B]**
- The three phone apps share one Dart core (models, API client, live updates, card and wallet widgets).
- Flutter's camera scanner and maps packages worked better for the POS and the rider.
- One language across all three apps meant fewer bugs.
The admin dashboard is still JavaScript (Next.js).

**16. Why separate carts per store? [Z]**
Each order goes from one shop, packed by one vendor and carried by one rider. Mixing stores would need splitting payment and escrow across several deliveries. Separate carts keep every order simple and auditable.

**17. How do the apps react when the admin changes a policy? [Z]**
The server broadcasts `config:update` over Socket.IO after saving. Apps reload their rules immediately, and also on resume and every 10 minutes.

**18. Does it scale? [Z]**
- The design does: stateless API, PostgreSQL with indexes, and an S3-compatible file store (Cloudflare R2 in production).
- Our test data is 1,000 users, 1,980 products and 3,626 orders.
- *Honest:* we have not load-tested the PR04 target (100 concurrent inventory requests per second). That is next.

**19. What is not finished? [Z]**
- SMS notifications (in-app only for now)
- Staff roles inside a shop
- Reviews
- Rider CNIC approval
- Rate limiting
- A load test

The functional requirements FR01–FR09 are all done.

**20. What did each of you build? [both]**
- **Bilal:** vendor app (POS, scanner, dual inventory, catalog, pick-pack-ready), rider app (tasks, GPS, simulated drive), payout and delivery-fee logic.
- **Zohaib:** customer app (carts, checkout, tracking, wallet), escrow, Vendra Pay and reconciliation, disputes, admin dashboard and policy engine.
- **Shared:** the backend core, database design and tests.
