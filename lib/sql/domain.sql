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
    
-- CREATE IF NOT EXISTS UNIQUE INDEX idx_domain_renew ON domain(renewed_at);
  