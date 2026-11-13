CREATE TABLE polar_live_checkouts (
 id TEXT PRIMARY KEY, uid TEXT NOT NULL, request_id TEXT NOT NULL, tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
 product_id TEXT NOT NULL, organization_id TEXT NOT NULL, external_id TEXT NOT NULL,
 minor INTEGER NOT NULL CHECK(minor>=0), currency TEXT NOT NULL, discount_id TEXT,
 created INTEGER NOT NULL, expires INTEGER NOT NULL, checked INTEGER NOT NULL DEFAULT 0,
 UNIQUE(uid,request_id)
);
CREATE INDEX polar_live_owner ON polar_live_checkouts(uid,checked);
CREATE TABLE polar_live_orders (
 id TEXT PRIMARY KEY, checkout_id TEXT NOT NULL REFERENCES polar_live_checkouts(id),
 active INTEGER NOT NULL CHECK(active IN (0,1)), revoked INTEGER NOT NULL CHECK(revoked IN (0,1)), modified INTEGER NOT NULL
);
ALTER TABLE polar_webhook_inbox ADD COLUMN processed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE polar_webhook_inbox ADD COLUMN attempted INTEGER NOT NULL DEFAULT 0;
CREATE INDEX polar_pending_events ON polar_webhook_inbox(environment,processed,attempted);
