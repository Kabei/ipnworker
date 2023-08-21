CREATE TABLE IF NOT EXISTS block(
  height BIGINT NOT NULL,
  creator BIGINT NOT NULL,
  hash BLOB NOT NULL,
  prev BLOB,
  hashfile BLOB,
  signature BLOB NOT NULL,
  round BIGINT NOT NULL,
  timestamp BIGINT NOT NULL,
  count INTEGER DEFAULT 0,
  size BIGINT DEFAULT 0,
  error BOOLEAN DEFAULT FALSE,
  vsn integer,
  PRIMARY KEY(height, creator)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS validator(
    id BIGINT PRIMARY KEY NOT NULL,
    hostname VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(30) NOT NULL,
    owner BLOB NOT NULL,
    pubkey BLOB NOT NULL,
    net_pubkey BLOB NOT NULL,
    avatar TEXT,
    fee_type TINYINT NOT NULL,
    fee DOUBLE NOT NULL,
    stake BIGINT NOT NULL DEFAULT 0,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);