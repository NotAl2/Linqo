-- Preserve existing grants; new requests use USD 4.99/6.99 in the maintainer tool.
CREATE TABLE manual_grants_new(
  receipt_hash TEXT PRIMARY KEY,
  uid TEXT NOT NULL REFERENCES manual_accounts(uid),
  tier TEXT NOT NULL CHECK(tier IN ('xl','xxl')),
  minor INTEGER NOT NULL CHECK((tier='xl' AND minor>=400) OR (tier='xxl' AND minor>=699)),
  currency TEXT NOT NULL CHECK(currency='USD'),
  verified_at INTEGER NOT NULL,
  revoked_at INTEGER,
  reason TEXT NOT NULL DEFAULT '' CHECK(reason IN ('','refund','chargeback','mistake'))
);
INSERT INTO manual_grants_new SELECT * FROM manual_grants;
DROP TABLE manual_grants;
ALTER TABLE manual_grants_new RENAME TO manual_grants;
CREATE INDEX manual_grants_owner ON manual_grants(uid,revoked_at);
