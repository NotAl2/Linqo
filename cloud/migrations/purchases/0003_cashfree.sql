-- Never discard a financial ledger during a provider switch. If this fails,
-- preserve the database and migrate actual paid licences deliberately.
CREATE TABLE empty_shop_guard(n INTEGER NOT NULL CHECK(n=0));
INSERT INTO empty_shop_guard SELECT COUNT(*) FROM bmc_purchases;
INSERT INTO empty_shop_guard SELECT COUNT(*) FROM bmc_refunds;
DROP TABLE empty_shop_guard;
DROP TABLE bmc_purchases;
DROP TABLE bmc_refunds;
DROP TABLE shop_sessions;

CREATE TABLE cashfree_orders(
  id TEXT PRIMARY KEY,
  uid TEXT NOT NULL,
  request_id TEXT NOT NULL,
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  minor INTEGER NOT NULL CHECK(minor IN (44900,64900)),
  currency TEXT NOT NULL CHECK(currency='INR'),
  environment TEXT NOT NULL CHECK(environment IN ('sandbox','production')),
  created INTEGER NOT NULL,
  expires INTEGER NOT NULL,
  session TEXT,
  checkout_key TEXT NOT NULL UNIQUE,
  checked INTEGER NOT NULL DEFAULT 0,
  UNIQUE(uid,request_id)
);
CREATE INDEX cashfree_orders_owner ON cashfree_orders(uid,checked);
CREATE TABLE cashfree_payments(
  id TEXT NOT NULL,
  environment TEXT NOT NULL,
  order_id TEXT NOT NULL REFERENCES cashfree_orders(id),
  minor INTEGER NOT NULL,
  captured INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(environment,id)
);
CREATE INDEX cashfree_payments_order ON cashfree_payments(order_id,captured);
CREATE TABLE cashfree_refunds(
  id TEXT NOT NULL,
  environment TEXT NOT NULL,
  order_id TEXT NOT NULL REFERENCES cashfree_orders(id),
  payment_id TEXT NOT NULL,
  minor INTEGER NOT NULL CHECK(minor>0),
  created INTEGER NOT NULL,
  PRIMARY KEY(environment,id)
);
