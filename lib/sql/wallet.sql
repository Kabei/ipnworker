CREATE TABLE IF NOT EXISTS wallet(
  id TEXT PRIMARY KEY NOT NULL,
  pubkey BLOB NOT NULL,
  validator BIGINT NOT NULL,
  created_at BIGINT NOT NULL
) WITHOUT ROWID;