-- Preserve all previous financial rows while allowing private INR 1 XXL orders.
CREATE TABLE cashfree_orders_new(
  id TEXT PRIMARY KEY, uid TEXT NOT NULL, request_id TEXT NOT NULL,
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  minor INTEGER NOT NULL CHECK(minor IN (100,39900,44900,64900)),
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

CREATE TABLE account_offers(
  uid TEXT PRIMARY KEY REFERENCES manual_accounts(uid),
  minor INTEGER NOT NULL CHECK(minor=100),
  enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),
  created INTEGER NOT NULL
);
CREATE TABLE gift_grants(
  reference TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES manual_accounts(uid),
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  reason TEXT NOT NULL CHECK(reason IN ('gift','testing')),
  created INTEGER NOT NULL, revoked_at INTEGER
);
CREATE INDEX gift_grants_owner ON gift_grants(uid,revoked_at);
