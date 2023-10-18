PREPARE insert_txs(bigint, bytea, integer, bytea, bigint, integer, text)
AS INSERT INTO history.txs VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE insert_block(bigint, bigint, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);

PREPARE insert_round(bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint, bigint, bigint, integer, bytea, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);

PREPARE insert_jackpot(bigint, bytea, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE insert_snapshot(bigint, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);
