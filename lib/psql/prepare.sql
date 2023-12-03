PREPARE insert_pay(bytea, numeric, bytea, bigint, integer, bytea, numeric)
AS INSERT INTO history.payments VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE insert_tx(bytea, bigint, integer, bigint, bytea, integer, integer, integer, integer, bytea, bytea)
AS INSERT INTO history.txs VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);

PREPARE insert_block(numeric, bigint, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);

PREPARE insert_round(numeric, bytea, bytea, bigint, bytea, numeric, numeric, bigint, bigint, bigint, integer, bigint, bytea, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);

PREPARE insert_jackpot(bigint, bytea, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE insert_snapshot(bigint, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);

PREPARE upsert_balance(bytea, bytea, numeric, jsonb)
AS INSERT INTO history.balance VALUES($1,$2,$3,$4)
ON CONFLICT (id,token) DO UPDATE SET balance = EXCLUDED.balance, map = EXCLUDED.map;
