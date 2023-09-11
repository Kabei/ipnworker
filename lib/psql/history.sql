BEGIN;

CREATE SCHEMA IF NOT EXISTS history;

CREATE TABLE IF NOT EXISTS history.rounds(
  "id" BIGINT PRIMARY KEY NOT NULL,
  "hash" BYTEA NOT NULL,
  "prev" BYTEA,
  "creator" BIGINT,
  "coinbase" BIGINT,
  "blocks" BIGINT,
  "timestamp" BIGINT
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
  "round" BIGINT NOT NULL,
  "signature" BYTEA NOT NULL,
  "timestamp" BIGINT NOT NULL,
  "count" INTEGER DEFAULT 0,
  "size" BIGINT DEFAULT 0,
  "rejected" INTEGER,
  "vsn" INTEGER
);

CREATE TABLE IF NOT EXISTS history.events(
  "hash" BYTEA NOT NULL,
  "block_id" BIGINT,
  "type" INTEGER NOT NULL,
  "from" BYTEA,
  "timestamp" BIGINT NOT NULL,
  "signature" BYTEA,
  "args" TEXT
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


PREPARE insert_event(bytea, bigint, integer, bytea, bigint, bytea, text)
AS INSERT INTO history.events VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE last_events(integer, integer)
AS SELECT hash, timestamp, "type", block_id, "from" FROM history.events ORDER BY block_id DESC, timestamp DESC LIMIT $1 OFFSET $2;

PREPARE get_details_event(bytea, bigint)
AS SELECT "signature", "args" FROM history.events WHERE hash = $1 AND block_id = $2 LIMIT 1;


PREPARE insert_block(bigint, bigint, bigint, bytea, bytea, bytea, bigint, bytea, bigint, integer, bigint, integer, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);

PREPARE last_blocks(integer, integer)
AS SELECT * FROM history.blocks ORDER BY id DESC LIMIT $1 OFFSET $2;


PREPARE insert_round(bigint, bytea, bytea, bigint, bigint, bigint, bigint)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7);

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