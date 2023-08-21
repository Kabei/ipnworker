CREATE TABLE IF NOT EXISTS token(
  id VARCHAR(20) PRIMARY KEY NOT NULL,
  owner BLOB NOT NULL,
  name TEXT NOT NULL,
  avatar TEXT,
  decimal TINYINT DEFAULT 0,
  symbol VARCHAR(5) NOT NULL,
  enabled BOOLEAN,
  supply BIGINT DEFAULT 0,
  burned BIGINT DEFAULT 0,
  max_supply BIGINT DEFAULT 0,
  props BLOB,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS domain(
  name TEXT PRIMARY KEY NOT NULL,
  owner BLOB NOT NULL,
  email TEXT,
  avatar TEXT,
  records BIGINT DEFAULT 0,
  enabled BOOLEAN DEFAULT TRUE,
  created_at BIGINT NOT NULL,
  renewed_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
) WITHOUT ROWID;
    
CREATE INDEX IF NOT EXISTS idx_domain_renew ON domain(renewed_at);
  