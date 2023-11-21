 CREATE SCHEMA IF NOT EXISTS history;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA,
  "prev" BYTEA,
  "creator" BIGINT,
  "signature" BYTEA,
  "coinbase" BIGINT,
  "reward" BIGINT,
  "count" BIGINT,
  "tx_count" BIGINT,
  "size" BIGINT,
  "status" INTEGER,
  "timestamp" BIGINT,
  "blocks" BYTEA,
  "extras" BYTEA
);

CREATE TABLE IF NOT EXISTS history.jackpot(
  "round_id" BIGINT NOT NULL,
  "winner" BYTEA NOT NULL,
  "amount" BIGINT,
  PRIMARY KEY("round_id", "winner")
);

CREATE TABLE IF NOT EXISTS history.snapshot(
  "round_id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "size" BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS history.blocks(
  "id" BIGINT PRIMARY KEY,
  "creator" BIGINT NOT NULL,
  "height" BIGINT NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "hashfile" BYTEA,
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
  "from" BYTEA,
  "nonce" BIGINT,
  "ix" integer,
  "block" BIGINT,
  "hash" BYTEA NOT NULL,
  "type" INTEGER,
  "status" INTEGER,
  "size" INTEGER,
  "ctype" INTEGER,
  "args" BYTEA,
  "signature" BYTEA
  PRIMARY KEY("from", "nonce")
);

CREATE TABLE IF NOT EXISTS history.balance(
  "id" BYTEA,
  "token" BYTEA,
  "balance" BIGINT,
  "lock" BIGINT,
  PRIMARY KEY("id", "token")
);

CREATE TABLE IF NOT EXISTS history.payments(
  "from" BYTEA,
  "nonce" INTEGER,
  "to" BYTEA,
  "round" BIGINT,
  "type" INTEGER,
  "token" BYTEA,
  "amount" BIGINT
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
