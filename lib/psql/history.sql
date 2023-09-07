BEGIN;

CREATE SCHEMA IF NOT EXISTS history;

DO $$
BEGIN
IF to_regtype('block_index') IS NULL THEN
  CREATE TYPE block_index AS (creator BIGINT, height BIGINT);
END IF;
END$$;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "blocks" BIGINT NOT NULL,
  "timestamp" BIGINT NOT NULL
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
  "index" block_index PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "hashfile" BYTEA,
  "round" BIGINT NOT NULL,
  "signature" BYTEA NOT NULL,
  "timestamp" BIGINT NOT NULL,
  "count" INTEGER DEFAULT 0,
  "size" BIGINT DEFAULT 0,
  "failures" INTEGER,
  "vsn" INTEGER
);

CREATE TABLE IF NOT EXISTS history.events(
  "hash" BYTEA NOT NULL,
  "timestamp" BIGINT NOT NULL,
  "type" INTEGER NOT NULL,
  "block" block_index,
  "from" BYTEA,
  "signature" BYTEA,
  "args" TEXT
);

CREATE INDEX IF NOT EXISTS events_block_idx ON history.events("block");


DO $$
BEGIN
IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
SELECT create_hypertable('history.rounds', 'timestamp', chunk_time_interval => 604800000, if_not_exists => TRUE);
SELECT create_hypertable('history.jackpot', 'timestamp', chunk_time_interval => 604800000, if_not_exists => TRUE);
SELECT create_hypertable('history.snapshot', 'timestamp', chunk_time_interval => 2592000000, if_not_exists => TRUE);
SELECT create_hypertable('history.blocks', 'timestamp', chunk_time_interval => 604800000, if_not_exists => TRUE);
SELECT create_hypertable('history.events', 'timestamp', chunk_time_interval => 86400000, if_not_exists => TRUE);
END IF;
END$$;


PREPARE insert_event(bytea, bigint, integer, block_index, bytea, bytea, text)
AS INSERT INTO history.events VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE last_events(integer, integer)
AS SELECT hash, timestamp, "type", block, "from" FROM history.events ORDER BY (block).creator, (block).height DESC, timestamp DESC LIMIT $1 OFFSET $2;

PREPARE get_details_event(bytea, integer)
AS SELECT "signature", "args" FROM history.events WHERE hash = $1 AND timestamp = $2 LIMIT 1;


PREPARE insert_block(block_index, bytea, bytea, bytea, bigint, bytea, bigint, integer, bigint, integer, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);

PREPARE last_blocks(integer, integer)
AS SELECT * FROM history.blocks ORDER BY "round", (index).creator, (index).height DESC LIMIT $1 OFFSET $2;


PREPARE insert_round(bigint, bytea, bytea, bigint, bigint)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5);

PREPARE last_rounds(integer, integer)
AS SELECT * FROM history.rounds ORDER BY "id" LIMIT $1 OFFSET $2;


PREPARE insert_jackpot(bigint, bytea, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE last_jackpots(integer, integer)
AS SELECT j.*, r."timestamp" FROM history.jackpot j INNER JOIN history.rounds r ON r.id = j.round_id ORDER BY "round_id" LIMIT $1 OFFSET $2;


PREPARE insert_snapshot(bigint, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);

PREPARE last_snapshots(integer, integer)
AS SELECT s.*, r."timestamp" FROM history.snapshot s INNER JOIN history.rounds r ON r.id = s.round_id ORDER BY "round_id" LIMIT $1 OFFSET $2;

COMMIT;