CREATE SCHEMA IF NOT EXISTS history;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA,
  "prev" BYTEA,
  "creator" BIGINT,
  "signature" BYTEA,
  "coinbase" BIGINT,
  "count" BIGINT,
  "tx_count" BIGINT,
  "size" BIGINT,
  "reason" INTEGER,
  "blocks" BYTEA,
  "extras" BYTEA
);

CREATE TABLE IF NOT EXISTS history.jackpot(
  "round_id" BIGINT NOT NULL,
  "winner_id" BYTEA NOT NULL,
  "amount" BIGINT,
  PRIMARY KEY("round_id", "winner_id")
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
  "signature" BYTEA NOT NULL,
  "round" BIGINT NOT NULL,
  "timestamp" BIGINT NOT NULL,
  "count" INTEGER DEFAULT 0,
  "rejected" INTEGER,
  "size" BIGINT DEFAULT 0,
  "vsn" INTEGER
);

CREATE TABLE IF NOT EXISTS history.events(
  "block_id" BIGINT,
  "hash" BYTEA NOT NULL,
  "type" INTEGER NOT NULL,
  "from" BYTEA,
  "timestamp" BIGINT NOT NULL,
  "nonce" BIGINT NOT NULL,
  "signature" BYTEA,
  "args" TEXT,
  PRIMARY KEY("block_id", "hash")
);

CREATE INDEX IF NOT EXISTS events_block_id_idx ON history.events("block_id");


DO $$
BEGIN
IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
SELECT create_hypertable('history.rounds', 'id', chunk_time_interval => 151200, if_not_exists => TRUE);
SELECT create_hypertable('history.jackpot', 'round_id', chunk_time_interval => 604800, if_not_exists => TRUE);
SELECT create_hypertable('history.snapshot', 'round_id', chunk_time_interval => 604800, if_not_exists => TRUE);
SELECT create_hypertable('history.blocks', 'id', chunk_time_interval => 7560000, if_not_exists => TRUE);
SELECT create_hypertable('history.events', 'block_id', chunk_time_interval => 7560000, if_not_exists => TRUE);
END IF;
END$$;
