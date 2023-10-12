PREPARE insert_event(bigint, bytea, integer, bytea, bigint, bigint, bytea, text)
AS INSERT INTO history.events VALUES($1,$2,$3,$4,$5,$6,$7,$8);

PREPARE last_events(integer, integer)
AS SELECT block_id, hash, "type", "from", timestamp FROM history.events ORDER BY block_id DESC, timestamp DESC LIMIT $1 OFFSET $2;

PREPARE get_details_event(bytea, bigint)
AS SELECT "signature", "args" FROM history.events WHERE hash = $1 AND block_id = $2 LIMIT 1;


PREPARE insert_block(bigint, bigint, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);

PREPARE last_blocks(integer, integer)
AS SELECT * FROM history.blocks ORDER BY id DESC LIMIT $1 OFFSET $2;


PREPARE insert_round(bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint, bigint, integer, bytea, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);

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