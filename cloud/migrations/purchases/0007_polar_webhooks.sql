CREATE TABLE polar_webhook_inbox (
  environment TEXT NOT NULL CHECK(environment IN ('sandbox','production')),
  id TEXT NOT NULL,
  type TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  hash TEXT NOT NULL,
  received INTEGER NOT NULL,
  PRIMARY KEY(environment,id)
);
CREATE INDEX polar_webhook_retention ON polar_webhook_inbox(received);
