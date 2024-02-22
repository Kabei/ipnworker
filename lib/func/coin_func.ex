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
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        to,
        token_id,
        amount
      )
      when is_integer(amount) and amount <= @max_tx_amount and
             account_id != to do
    bt = BalanceTrace.new(account_id)
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

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
        |> Map.put(:supply, TokenSupply.output(supply))
    end
  end

  def multisend(
        %{id: from, validator: %{fa: fa, fb: fb}, size: size},
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

    BalanceTrace.new(from)
    |> BalanceTrace.multi_requires!([{token_id, total}, {@token, fees}])
    |> BalanceTrace.output()
  end

  def refund(%{id: account_id}, hash16)
      when byte_size(hash16) == 64 do
    db_ref = :persistent_term.get(:main_conn)
    hash = Base.decode16!(hash16, case: :mixed)

    case Sqlite.exists?("exists_refund", [hash, account_id]) do
      false ->
        raise IppanError, "Hash refund not exists"

      true ->
        :ok
    end
  end

  def lock(%{id: account_id}, to, token_id, amount)
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
        BalanceTrace.new(to)
        |> BalanceTrace.requires!(@token, amount)
        |> BalanceTrace.output()
    end
  end

  def unlock(%{id: account_id}, to, token_id, amount)
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
        BalanceTrace.new(to)
        |> BalanceTrace.can_unlock!(token_id, amount)

        :ok
    end
  end

  def burn(%{id: account_id}, token_id, amount) when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      Token.has_prop?(token, "burn") == false ->
        raise IppanError, "Burn property missing"

      true ->
        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.output()
    end
  end

  def burn(%{id: account_id}, to, token_id, amount) when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      Token.has_prop?(token, "burn") == false ->
        raise IppanError, "Burn property missing"

      token.owner != account_id ->
        raise IppanError, "Unauthorised"

      true ->
        BalanceTrace.new(to)
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.output()
    end
  end

  def reload(%{id: account_id}, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    %{env: env, props: props} = Token.get(token_id)

    if "reload" not in props, do: raise(IppanError, "Reload property is missing")

    acc_type = Map.get(env, "reload.accType")

    if acc_type do
      cond do
        acc_type == "anon" and not Match.wallet_address?(account_id) ->
          raise IppanError, "Your account type is not allowed"

        acc_type == "public" and not Match.username?(account_id) ->
          raise IppanError, "Your account type is not allowed"
      end
    end

    stats = Stats.new()
    round_id = Stats.rounds(stats)
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(dets, :cache_balance)
    %{env: %{"reload.times" => times}} = Token.get(token_id)

    key = DetsPlux.tuple(account_id, token_id)
    {_balance, map} = DetsPlux.get_cache(dets, tx, key, {0, %{}})
    last_reload = Map.get(map, "lastReload", 0)
    req_time = last_reload + times

    if last_reload > 0 and round_id < req_time,
      do: raise(IppanError, "It's already recharged. Wait for #{req_time}")

    price = Map.get(env, "reload.price", 0)

    ret =
      if price != 0 do
        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
      end

    DetsPlux.update_element(tx, key, 3, Map.put(map, "lastReload", round_id))

    ret
  end

  def stream(%{id: account_id}, payer, token_id, amount) do
    db_ref = :persistent_term.get(:main_conn)

    case SubPay.get(db_ref, account_id, payer, token_id) do
      nil ->
        raise IppanError, "Payment not authorized"

      %{extra: extra, last_round: last_round} ->
        max_amount = Map.get(extra, "max_amount", 0)
        stats = Stats.new()
        round_id = Stats.rounds(stats)
        %{env: %{"stream.times" => interval}} = Token.get(token_id)

        cond do
          max_amount != 0 and max_amount < amount ->
            raise IppanError, "Exceeded amount"

          last_round + interval < round_id ->
            raise IppanError, "Paystream already used"

          true ->
            %{env: %{"stream.times" => times}, props: props} = Token.get(token_id)

            if "stream" not in props, do: raise(IppanError, "Stream property is missing")

            dets = DetsPlux.get(:balance)
            tx = DetsPlux.tx(dets, :balance)
            key = DetsPlux.tuple(account_id, token_id)
            {_balance, map} = DetsPlux.get_cache(dets, tx, key, {0, %{}})
            stats = Stats.new()
            round_id = Stats.rounds(stats)
            last_round = Map.get(map, "lastStream", 0)

            req_round = last_round + times

            if last_round != 0 and round_id < req_round,
              do: raise(IppanError, "it's already used. Wait for round ##{req_round}")

            BalanceTrace.new(payer)
            |> BalanceTrace.requires!(token_id, amount)
            |> BalanceTrace.output()
        end
    end
  end

  def auth(
        %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        token_id,
        to,
        auth
      )
      when is_boolean(auth) do
    db_ref = :persistent_term.get(:main_conn)
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(dets, :balance)
    token = Token.get(token_id)

    cond do
      token.owner != account_id ->
        raise IppanError, "Unauthorized"

      Token.has_prop?(token, "auth") == false ->
        raise IppanError, "Property auth not exists"

      DetsPlux.member_tx?(dets, tx, to) == false ->
        raise IppanError, "#{to} account not exists"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(token_id, fees)
        |> BalanceTrace.output()
    end
  end
end
