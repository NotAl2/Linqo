CREATE TABLE consent(owner TEXT PRIMARY KEY, enabled INTEGER NOT NULL, version INTEGER NOT NULL, changed INTEGER NOT NULL);
CREATE TABLE samples(id TEXT PRIMARY KEY, owner TEXT NOT NULL, day TEXT NOT NULL, payload TEXT NOT NULL, sha256 TEXT NOT NULL, bytes INTEGER NOT NULL, created INTEGER NOT NULL, exported INTEGER);
CREATE INDEX samples_owner ON samples(owner,created);
CREATE INDEX samples_created ON samples(created,id);
CREATE TABLE daily(owner TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY(owner,day));
CREATE TABLE deletions(sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, created INTEGER NOT NULL);
CREATE TABLE registry(sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, owner TEXT NOT NULL, created INTEGER NOT NULL);
CREATE INDEX registry_owner ON registry(owner,sequence);
CREATE TABLE intake_budget(id INTEGER PRIMARY KEY CHECK(id=1), bytes INTEGER NOT NULL);
INSERT INTO intake_budget VALUES(1,0);
CREATE TRIGGER sample_insert AFTER INSERT ON samples BEGIN
  INSERT INTO registry(id,owner,created) VALUES(NEW.id,NEW.owner,NEW.created);
  UPDATE intake_budget SET bytes=bytes+NEW.bytes WHERE id=1;
  INSERT INTO daily(owner,day,count) VALUES(NEW.owner,NEW.day,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1;
  INSERT INTO daily(owner,day,count) VALUES('*',NEW.day,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1;
END;
CREATE TRIGGER sample_delete AFTER DELETE ON samples BEGIN
  UPDATE intake_budget SET bytes=bytes-OLD.bytes WHERE id=1;
END;
