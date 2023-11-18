PREPARE insert_pay(bytea, integer, bytea, bigint, integer, bytea, bigint)
AS INSERT INTO history.payments VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE insert_tx(bytea, bigint, integer, bigint, bytea, integer, integer, integer, integer, bytea)
AS INSERT INTO history.txs VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);

PREPARE insert_block(bigint, bigint, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);

PREPARE insert_round(bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint, bigint, bigint, integer, bigint, bytea, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);

PREPARE insert_jackpot(bigint, bytea, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE insert_snapshot(bigint, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);

PREPARE upsert_balance(bytea, bytea, bigint, bigint)
AS INSERT INTO history.balance VALUES($1,$2,$3,$4)
ON CONFLICT (id,token) DO UPDATE SET balance = EXCLUDED.balance, lock = EXCLUDED.lock;
