-- Refuse to discard any legacy financial history. Production was checked empty
-- before this replacement. Keep migrations append-only for existing installs.
CREATE TABLE empty_legacy_guard(n INTEGER NOT NULL CHECK(n=0));
INSERT INTO empty_legacy_guard SELECT COUNT(*) FROM payments;
INSERT INTO empty_legacy_guard SELECT COUNT(*) FROM orders;
DROP TABLE empty_legacy_guard;
DROP TABLE payments;
DROP TABLE orders;
DROP TABLE events;

CREATE TABLE shop_sessions(
  claim_hash TEXT PRIMARY KEY,
  uid TEXT NOT NULL,
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  product_id TEXT NOT NULL,
  cents INTEGER NOT NULL,
  issued INTEGER NOT NULL,
  expires INTEGER NOT NULL
);
CREATE INDEX shop_sessions_expiry ON shop_sessions(expires);
CREATE TABLE bmc_purchases(
  id TEXT PRIMARY KEY,
  uid TEXT,
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  product_id TEXT NOT NULL,
  cents INTEGER NOT NULL,
  currency TEXT NOT NULL CHECK(currency='USD'),
  captured INTEGER NOT NULL DEFAULT 0,
  refunded INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL,
  claim_hash TEXT UNIQUE
);
CREATE INDEX bmc_purchases_owner ON bmc_purchases(uid,captured,refunded);
CREATE TABLE bmc_refunds(id TEXT PRIMARY KEY,created INTEGER NOT NULL);
