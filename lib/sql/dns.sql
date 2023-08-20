CREATE TABLE IF NOT EXISTS dns(
  domain TEXT NOT NULL,
  name TEXT NOT NULL,
  type TINYINT NOT NULL,
  data TEXT,
  ttl INTEGER DEFAULT 0,
  hash BLOB NOT NULL,
  PRIMARY KEY(domain, hash)
) WITHOUT ROWID;