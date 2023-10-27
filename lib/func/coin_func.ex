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
          validator: %{fee: vfee, fee_type: fee_type}
        },
        to,
        token_id,
        amount
      )
      when is_integer(amount) and amount <= @max_tx_amount and
             account_id != to do
    bt = BalanceTrace.new(account_id)
    fees = Utils.calc_fees!(fee_type, vfee, amount, size)

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

  def coinbase(%{id: account_id}, token_id, outputs)
      when length(outputs) > 0 do
    db_ref = :persistent_term.get(:main_conn)
    %{max_supply: max_supply} = token = Token.get(token_id)

    cond do
      token.owner != account_id ->
        raise IppanError, "Invalid owner"

      not Token.has_prop?(token, "coinbase") ->
        raise IppanError, "Token property invalid"

      true ->
        total =
          Enum.reduce(outputs, 0, fn [account, amount], acc ->
            cond do
              amount <= 0 ->
                raise ArgumentError, "Amount must be positive number"

              amount > @max_tx_amount ->
                raise ArgumentError, "Amount exceeded max value"

              not Match.account?(account) ->
                raise ArgumentError, "Account ID invalid"

              true ->
                amount + acc
            end
          end)

        if max_supply != 0 do
          current_supply = TokenSupply.cache(token_id) |> TokenSupply.get()

          if current_supply + total > max_supply do
            raise IppanError, "max supply exceeded"
          end
        end
    end
  end

  def multisend(
        %{id: from, validator: %{fee: vfee, fee_type: fee_type}, size: size},
        token_id,
        outputs
      )
      when length(outputs) > 0 do
    total =
      Enum.reduce(outputs, 0, fn [to, amount], acc ->
        cond do
          amount <= 0 ->
            raise ArgumentError, "Amount must be positive number"

          amount > @max_tx_amount ->
            raise ArgumentError, "Amount exceeded max value"

          not Match.account?(to) ->
            raise ArgumentError, "Account ID invalid"

          to == from ->
            raise ArgumentError, "Wrong receiver"

          true ->
            amount + acc
        end
      end)

    fees = Utils.calc_fees!(fee_type, vfee, total, size)

    BalanceTrace.new(from)
    |> BalanceTrace.requires!(token_id, total + fees)
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

  def lock(%{id: account_id}, to_id, token_id, amount)
      when is_integer(amount) do
    db_ref = :persistent_term.get(:main_conn)
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(:balance)
    token = Token.get(token_id)
    balance_key = DetsPlux.tuple(to_id, token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "TokenID not exists"

      token.owner != account_id ->
        raise IppanError, "unauthorised"

      not Token.has_prop?(token, "lock") ->
        raise IppanError, "Invalid property"

      true ->
        BalanceStore.requires!(dets, tx, balance_key, amount)
    end
  end

  def unlock(%{id: account_id}, to_id, token_id, amount)
      when is_integer(amount) do
    db_ref = :persistent_term.get(:main_conn)
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(:balance)
    token = Token.get(token_id)
    balance_key = DetsPlux.tuple(to_id, token_id)

    cond do
      is_nil(token) ->
        raise IppanError, "TokenID not exists"

      token.owner != account_id ->
        raise IppanError, "unauthorised"

      not Token.has_prop?(token, "lock") ->
        raise IppanError, "Invalid property"

      true ->
        BalanceStore.requires!(dets, tx, balance_key, amount)
    end
  end

  def burn(%{id: account_id}, token_id, amount) when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      not Token.has_prop?(token, "burn") ->
        raise IppanError, "Token property invalid"

      true ->
        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(token_id, amount)
    end
  end
end
