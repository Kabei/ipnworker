defmodule Ippan.Funx.Coin do
  alias Ippan.{Token, Utils}
  require Sqlite
  require BalanceStore
  require RegPay
  require Token

  @app Mix.Project.config()[:app]
  @refund_timeout Application.compile_env(@app, :timeout_refund)
  @token Application.compile_env(@app, :token)

  def send(
        source = %{
          id: from,
          validator: %{fa: fa, fb: fb, owner: vOwner},
          size: size
        },
        to,
        token_id,
        amount
      ) do
    is_validator = vOwner == from
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    tfees = Utils.calc_fees(fa, fb, size)

    BalanceStore.pay from, token_id, amount, tfees do
      BalanceStore.send(from, to, token_id, amount)

      reserve = Utils.calc_reserve(tfees)
      fees = tfees - reserve

      if is_validator do
        BalanceStore.burn(from, @token, fees)
        BalanceStore.reserve(from, reserve)
      else
        validator_balance = BalanceStore.load(vOwner, @token)
        BalanceStore.fees(from, validator_balance, fees)
        BalanceStore.reserve(from, reserve)
      end
    end
  end

  def send(source, to, token_id, amount, _note) do
    send(source, to, token_id, amount)
  end

  def send(
        source = %{hash: hash, id: from, round: round_id},
        to,
        token_id,
        amount,
        _note,
        true
      ) do
    send(source, to, token_id, amount)

    db_ref = :persistent_term.get(:main_conn)

    Sqlite.step("insert_refund", [
      hash,
      from,
      to,
      token_id,
      amount,
      round_id + @refund_timeout
    ])
  end

  def coinbase(
        source = %{
          id: from,
          validator: %{fa: fa, fb: fb, owner: vOwner},
          size: size
        },
        token_id,
        outputs
      ) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    tfees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_fee(from, vOwner, tfees) do
      :error ->
        :error

      _ ->
        total =
          for [account, value] <- outputs do
            BalanceStore.coinbase(account, token_id, value)
            value
          end
          |> Enum.sum()

        supply = TokenSupply.new(token_id)
        TokenSupply.add(supply, total)
    end
  end

  def multisend(
        source = %{
          id: from,
          validator: %{fa: fa, fb: fb, owner: vOwner},
          size: size
        },
        token_id,
        outputs
      ) do
    is_validator = vOwner == from
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    tfees = Utils.calc_fees(fa, fb, size)
    total = Enum.reduce(outputs, 0, fn [_to, amount], acc -> acc + amount end)

    BalanceStore.pay from, token_id, total, tfees do
      Enum.each(outputs, fn [to, amount] ->
        BalanceStore.send(from, to, token_id, amount)
      end)

      reserve = Utils.calc_reserve(tfees)
      fees = tfees - reserve

      if is_validator do
        BalanceStore.burn(from, @token, fees)
        BalanceStore.reserve(from, reserve)
      else
        validator_balance = BalanceStore.load(vOwner, @token)
        BalanceStore.fees(from, validator_balance, fees)
        BalanceStore.reserve(from, reserve)
      end
    end
  end

  def multisend(source, token_id, outputs, _note) do
    multisend(source, token_id, outputs)
  end

  def drop(source = %{id: account_id}, token_id, amount) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    BalanceStore.pay_drop(account_id, token_id, amount)
  end

  def burn(source, to, token_id, amount) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    BalanceStore.pay_burn(to, token_id, amount)
  end

  def refund(source = %{id: account_id}, sender, nonce) do
    db_ref = :persistent_term.get(:main_conn)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    case Sqlite.step("get_refund", [sender, nonce, account_id]) do
      {:row, [to, token_id, refund_amount]} ->
        Sqlite.step("delete_refund", [sender, nonce])
        BalanceStore.refund(account_id, to, token_id, refund_amount)

      _ ->
        :error
    end
  end

  def lock(source, to, token_id, amount) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    BalanceStore.lock(to, token_id, amount)
  end

  def unlock(source, to, token_id, amount) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    BalanceStore.unlock(to, token_id, amount)
  end

  def reload(source = %{id: account_id, round: round_id}, token_id) do
    db_ref = :persistent_term.get(:main_conn)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    %{env: env} = Token.get(token_id)
    %{"reload.amount" => value, "reload.every" => times} = env

    target = DetsPlux.tuple(account_id, token_id)
    {balance, map} = DetsPlux.get_cache(db, tx, target, {0, %{}})
    init_reload = Map.get(map, "initReload", round_id)
    last_reload = Map.get(map, "lastReload", round_id)
    mult = calc_reload_mult(round_id, init_reload, last_reload, times)

    case env do
      %{"reload.expiry" => expiry} ->
        cond do
          round_id - last_reload > expiry ->
            new_map = map |> Map.delete("initReload") |> Map.delete("lastReload")
            DetsPlux.update_element(tx, target, 3, new_map)
            BalanceStore.expired(target, token_id, balance)

          true ->
            new_map =
              map
              |> Map.put("initReload", init_reload)
              |> Map.put("lastReload", round_id)

            DetsPlux.update_element(tx, target, 3, new_map)
            BalanceStore.reload(target, token_id, value * mult)
        end

      _ ->
        new_map =
          map
          |> Map.put("initReload", init_reload)
          |> Map.put("lastReload", round_id)

        DetsPlux.update_element(tx, target, 3, new_map)
        BalanceStore.reload(target, token_id, value * mult)
    end
  end

  defp calc_reload_mult(round_id, init_round, _last_round, _times) when round_id == init_round,
    do: 1

  defp calc_reload_mult(round_id, init_round, last_round, times) do
    div(round_id - init_round, times) - div(last_round - init_round, times)
  end

  def auth(
        source = %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        to,
        token_id,
        auth
      ) do
    fees = Utils.calc_fees(fa, fb, size)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)

    case BalanceStore.pay_fee(account_id, vOwner, fees) do
      :error ->
        :error

      _ ->
        key_to = DetsPlux.tuple(to, token_id)
        {_balance, map} = DetsPlux.get_cache(db, tx, key_to, {0, %{}})

        new_map =
          if auth do
            Map.put(map, "auth", true)
          else
            Map.delete(map, "auth")
          end

        DetsPlux.update_element(tx, key_to, 3, new_map)
    end
  end
end
