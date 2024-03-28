 CREATE SCHEMA IF NOT EXISTS history;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" NUMERIC PRIMARY KEY NOT NULL,
  "hash" BYTEA,
  "prev" BYTEA,
  "creator" TEXT,
  "signature" BYTEA,
  "reward" NUMERIC,
  "count" BIGINT,
  "tx_count" BIGINT,
  "size" BIGINT,
  "status" INTEGER,
  "timestamp" BIGINT,
  "extra" BYTEA
);

CREATE TABLE IF NOT EXISTS history.jackpot(
  "round_id" NUMERIC NOT NULL,
  "winner" TEXT NOT NULL,
  "amount" NUMERIC,
  PRIMARY KEY("round_id", "winner")
);

CREATE TABLE IF NOT EXISTS history.snapshot(
  "round_id" NUMERIC PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "size" BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS history.blocks(
  "id" NUMERIC PRIMARY KEY,
  "creator" TEXT NOT NULL,
  "height" BIGINT NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "filehash" BYTEA,
  "signature" BYTEA,
  "round" BIGINT NOT NULL,
  "timestamp" BIGINT,
  "count" INTEGER DEFAULT 0,
  "rejected" INTEGER,
  "size" BIGINT DEFAULT 0,
  "status" INTEGER,
  "vsn" INTEGER
);

CREATE TABLE IF NOT EXISTS history.txs(
  "from" TEXT,
  "nonce" NUMERIC,
  "ix" INTEGER,
  "block" BIGINT,
  "hash" BYTEA NOT NULL,
  "type" INTEGER,
  "status" INTEGER,
  "size" INTEGER,
  "ctype" INTEGER,
  "args" BYTEA,
  "signature" BYTEA,
  PRIMARY KEY("from", "nonce")
);

CREATE TABLE IF NOT EXISTS history.balance(
  "id" TEXT,
  "token" TEXT,
  "balance" NUMERIC,
  "map" JSONB,
  PRIMARY KEY("id", "token")
);

CREATE TABLE IF NOT EXISTS history.payments(
  "from" TEXT,
  "nonce" NUMERIC,
  "to" TEXT,
  "round" BIGINT,
  "type" INTEGER,
  "token" TEXT,
  "amount" NUMERIC
);

CREATE INDEX IF NOT EXISTS txs_hash_idx ON history.txs("hash");

CREATE INDEX IF NOT EXISTS payments_from_idx ON history.payments("from") WHERE "from" IS NOT NULL;

CREATE INDEX IF NOT EXISTS payments_to_idx ON history.payments("to") WHERE "to" IS NOT NULL;

DO $$
BEGIN
IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
SELECT create_hypertable('history.rounds', 'id', chunk_time_interval => 151200, if_not_exists => TRUE);
SELECT create_hypertable('history.jackpot', 'round_id', chunk_time_interval => 604800, if_not_exists => TRUE);
SELECT create_hypertable('history.snapshot', 'round_id', chunk_time_interval => 604800, if_not_exists => TRUE);
SELECT create_hypertable('history.blocks', 'id', chunk_time_interval => 7560000, if_not_exists => TRUE);
SELECT create_hypertable('history.txs', 'block', chunk_time_interval => 7560000, if_not_exists => TRUE);
SELECT create_hypertable('history.payments', 'round', chunk_time_interval => 7560000, if_not_exists => TRUE);
ELSE
CREATE INDEX IF NOT EXISTS txs_block_idx ON history.txs("block", "ix" ASC);
CREATE INDEX IF NOT EXISTS payments_round_idx ON history.payments("round");
END IF;
END$$;
