defmodule Ippan.Func.Coin do
  alias Ippan.{Token, Utils}
  require Sqlite
  require BalanceStore
  require Token
  require Logger

  @app Mix.Project.config()[:app]
  @max_tx_amount Application.compile_env(@app, :max_tx_amount)
  @note_max_size Application.compile_env(@app, :note_max_size)
  @token Application.compile_env(@app, :token)

  def send(
        %{
          id: account_id,
          dets: dets,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        to,
        token_id,
        amount
      )
      when is_integer(amount) and amount > 0 and amount <= @max_tx_amount and
             account_id != to do
    bt = BalanceTrace.new(account_id, dets.balance)
    fees = Utils.calc_fees(fa, fb, size)

    case token_id == @token do
      true ->
        BalanceTrace.requires!(bt, token_id, amount + fees)

      false ->
        BalanceTrace.multi_requires!(bt, [{token_id, amount}, {@token, fees}])
    end
    |> BalanceTrace.output()
  end

  def send(source, to, token_id, amount, note) when byte_size(note) <= @note_max_size do
    send(source, to, token_id, amount)
  end

  def send(source, to, token_id, amount, note, true) when byte_size(note) <= @note_max_size do
    send(source, to, token_id, amount)
  end

  def coinbase(
        %{
          id: account_id,
          dets: dets,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        token_id,
        outputs
      )
      when length(outputs) > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "Token not exists"

      token.owner != account_id ->
        raise IppanError, "Invalid owner"

      Token.has_prop?(token, "coinbase") == false ->
        raise IppanError, "Token property invalid"

      true ->
        total =
          Enum.reduce(outputs, 0, fn [account, amount], acc ->
            cond do
              not is_integer(amount) or amount < 0 or amount > @max_tx_amount ->
                raise ArgumentError, "Invalid amount"

              not Match.account?(account) ->
                raise ArgumentError, "Account ID invalid"

              true ->
                amount + acc
            end
          end)

        %{max_supply: max_supply} = token

        supply =
          TokenSupply.cache(token_id)
          |> TokenSupply.requires!(total, max_supply)

        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
        |> Map.put(:supply, TokenSupply.output(supply))
    end
  end

  def multisend(
        %{id: from, dets: dets, validator: %{fa: fa, fb: fb}, size: size},
        token_id,
        outputs,
        note \\ ""
      )
      when length(outputs) > 0 and byte_size(note) <= @note_max_size do
    total =
      Enum.reduce(outputs, 0, fn [to, amount], acc ->
        cond do
          not is_integer(amount) or amount < 0 or amount > @max_tx_amount ->
            raise ArgumentError, "Amount must be positive number"

          not Match.account?(to) ->
            raise ArgumentError, "Account ID invalid"

          to == from ->
            raise ArgumentError, "Wrong receiver"

          true ->
            amount + acc
        end
      end)

    fees = Utils.calc_fees(fa, fb, size)

    BalanceTrace.new(from, dets.balance)
    |> BalanceTrace.multi_requires!([{token_id, total}, {@token, fees}])
    |> BalanceTrace.output()
  end

  def refund(%{id: account_id}, sender, nonce)
      when is_integer(nonce) and nonce >= 0 do
    db_ref = :persistent_term.get(:main_conn)

    case Sqlite.exists?("exists_refund", [sender, nonce, account_id]) do
      false ->
        raise IppanError, "Transaction does not exists"

      true ->
        :ok
    end
  end

  def lock(%{id: account_id, dets: dets}, to, token_id, amount)
      when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "Invalid token ID"

      token.owner != account_id ->
        raise IppanError, "Unauthorised"

      Token.has_prop?(token, "lock") == false ->
        raise IppanError, "lock property is missing"

      true ->
        BalanceTrace.new(to, dets.balance)
        |> BalanceTrace.requires!(@token, amount)
        |> BalanceTrace.output()
    end
  end

  def unlock(%{id: account_id, dets: dets}, to, token_id, amount)
      when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "TokenID not exists"

      token.owner != account_id ->
        raise IppanError, "Unauthorised"

      Token.has_prop?(token, "lock") == false ->
        raise IppanError, "lock property missing"

      true ->
        BalanceTrace.new(to, dets.balance)
        |> BalanceTrace.can_unlock!(token_id, amount)

        :ok
    end
  end

  def burn(%{id: account_id, dets: dets}, token_id, amount)
      when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      Token.has_prop?(token, "burn") == false ->
        raise IppanError, "Burn property missing"

      true ->
        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.output()
    end
  end

  def burn(%{id: account_id, dets: dets}, to, token_id, amount)
      when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      Token.has_prop?(token, "burn") == false ->
        raise IppanError, "Burn property missing"

      token.owner != account_id ->
        raise IppanError, "Unauthorised"

      true ->
        BalanceTrace.new(to, dets.balance)
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.output()
    end
  end

  def reload(%{id: account_id, dets: dets}, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    %{env: env, props: props} = Token.get(token_id)

    if "reload" not in props, do: raise(IppanError, "Reload property is missing")

    stats = Stats.new(dets.stats)
    round_id = Stats.get(stats, "last_round")
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, dets.balance)
    %{"reload.every" => times} = env

    key = DetsPlux.tuple(account_id, token_id)
    {_balance, map} = DetsPlux.get_cache(db, tx, key, {0, %{}})
    last_reload = Map.get(map, "lastReload", 0)
    req_time = last_reload + times

    if last_reload > 0 and round_id < req_time,
      do: raise(IppanError, "It's already recharged. Wait for Round ##{req_time}")

    if Map.get(env, "reload.auth") == true and Map.get(map, "auth") == false,
      do: raise(IppanError, "Unauthorized account")

    price = Map.get(env, "reload.price", 0)

    ret =
      if price != 0 do
        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
      end

    DetsPlux.update_element(tx, key, 3, Map.put(map, "lastReload", round_id))

    ret
  end

  def auth(
        %{
          id: account_id,
          dets: dets,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        to,
        token_id,
        auth
      )
      when is_boolean(auth) do
    db_ref = :persistent_term.get(:main_conn)
    wallet = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(wallet, dets.wallet)
    token = Token.get(token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "Token #{token_id} not exists"

      token.owner != account_id ->
        raise IppanError, "Unauthorized"

      DetsPlux.member_tx?(wallet, tx, to) == false ->
        raise IppanError, "Account #{to} not exists"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end
end
