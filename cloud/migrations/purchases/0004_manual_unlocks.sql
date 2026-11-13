CREATE TABLE manual_accounts(uid TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE);
CREATE TABLE manual_grants(
  receipt_hash TEXT PRIMARY KEY,
  uid TEXT NOT NULL REFERENCES manual_accounts(uid),
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  minor INTEGER NOT NULL CHECK((tier='xl' AND minor>=400) OR (tier='xxl' AND minor>=700)),
  currency TEXT NOT NULL CHECK(currency='USD'),
  verified_at INTEGER NOT NULL,
  revoked_at INTEGER,
  reason TEXT NOT NULL DEFAULT '' CHECK(reason IN ('','refund','chargeback','mistake'))
);
CREATE INDEX manual_grants_owner ON manual_grants(uid,revoked_at);

-- Keep historic INR 449 XL orders and their payment/refund references intact.
-- SQLite cannot widen a CHECK constraint in place; copy children before dropping.
CREATE TABLE cashfree_orders_new(
  id TEXT PRIMARY KEY, uid TEXT NOT NULL, request_id TEXT NOT NULL,
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  minor INTEGER NOT NULL CHECK(minor IN (39900,44900,64900)),
  currency TEXT NOT NULL CHECK(currency='INR'),
  environment TEXT NOT NULL CHECK(environment IN ('sandbox','production')),
  created INTEGER NOT NULL, expires INTEGER NOT NULL, session TEXT,
  checkout_key TEXT NOT NULL UNIQUE, checked INTEGER NOT NULL DEFAULT 0,
  UNIQUE(uid,request_id)
);
INSERT INTO cashfree_orders_new SELECT * FROM cashfree_orders;
CREATE TABLE cashfree_payments_new(
  id TEXT NOT NULL, environment TEXT NOT NULL,
  order_id TEXT NOT NULL REFERENCES cashfree_orders_new(id),
  minor INTEGER NOT NULL, captured INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(environment,id)
);
INSERT INTO cashfree_payments_new SELECT * FROM cashfree_payments;
CREATE TABLE cashfree_refunds_new(
  id TEXT NOT NULL, environment TEXT NOT NULL,
  order_id TEXT NOT NULL REFERENCES cashfree_orders_new(id),
  payment_id TEXT NOT NULL, minor INTEGER NOT NULL CHECK(minor>0),
  created INTEGER NOT NULL, PRIMARY KEY(environment,id)
);
INSERT INTO cashfree_refunds_new SELECT * FROM cashfree_refunds;
DROP TABLE cashfree_refunds;
DROP TABLE cashfree_payments;
DROP TABLE cashfree_orders;
ALTER TABLE cashfree_orders_new RENAME TO cashfree_orders;
ALTER TABLE cashfree_payments_new RENAME TO cashfree_payments;
ALTER TABLE cashfree_refunds_new RENAME TO cashfree_refunds;
CREATE INDEX cashfree_orders_owner ON cashfree_orders(uid,checked);
CREATE INDEX cashfree_payments_order ON cashfree_payments(order_id,captured);
