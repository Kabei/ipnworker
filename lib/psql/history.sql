set AUTOCOMMIT off;
BEGIN;
CREATE SCHEMA IF NOT EXISTS history;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "creator" BIGINT,
  "signature" BYTEA,
  "coinbase" BIGINT,
  "count" BIGINT,
  "tx_count" BIGINT,
  "size" BIGINT,
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


PREPARE insert_event(bigint, bytea, integer, bytea, bigint, bytea, text)
AS INSERT INTO history.events VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE last_events(integer, integer)
AS SELECT block_id, hash, timestamp, "type", "from" FROM history.events ORDER BY block_id DESC, timestamp DESC LIMIT $1 OFFSET $2;

PREPARE get_details_event(bytea, bigint)
AS SELECT "signature", "args" FROM history.events WHERE hash = $1 AND block_id = $2 LIMIT 1;


PREPARE insert_block(bigint, bigint, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);

PREPARE last_blocks(integer, integer)
AS SELECT * FROM history.blocks ORDER BY id DESC LIMIT $1 OFFSET $2;


PREPARE insert_round(bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint, bigint, bytea, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);

PREPARE last_rounds(integer, integer)
AS SELECT * FROM history.rounds ORDER BY "id" LIMIT $1 OFFSET $2;


PREPARE insert_jackpot(bigint, bytea, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE last_jackpots(integer, integer)
AS SELECT * FROM history.jackpot ORDER BY round_id LIMIT $1 OFFSET $2;


PREPARE insert_snapshot(bigint, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);

PREPARE last_snapshots(integer, integer)
AS SELECT * FROM history.snapshot ORDER BY round_id LIMIT $1 OFFSET $2;

COMMIT;