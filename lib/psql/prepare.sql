PREPARE insert_pay(text, numeric, text, bigint, integer, text, numeric)
AS INSERT INTO history.payments VALUES($1,$2,$3,$4,$5,$6,$7);

PREPARE insert_tx(text, numeric, integer, bigint, bytea, integer, integer, integer, integer, bytea, bytea)
AS INSERT INTO history.txs VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);

PREPARE insert_block(numeric, text, bigint, bytea, bytea, bytea, bytea, bigint, bigint, integer, integer, bigint, integer, integer)
AS INSERT INTO history.blocks VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);

PREPARE insert_round(numeric, bytea, bytea, text, bytea, numeric, bigint, bigint, bigint, integer, bigint, bytea)
AS INSERT INTO history.rounds VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);

PREPARE insert_jackpot(numeric, text, bigint)
AS INSERT INTO history.jackpot VALUES($1,$2,$3);

PREPARE insert_snapshot(numeric, bytea, bigint)
AS INSERT INTO history.snapshot VALUES($1,$2,$3);

PREPARE upsert_balance(text, text, numeric, jsonb)
AS INSERT INTO history.balance VALUES($1,$2,$3,$4)
ON CONFLICT (id,token) DO UPDATE SET balance = EXCLUDED.balance, map = EXCLUDED.map;
