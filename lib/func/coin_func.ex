defmodule Ippan.Func.Coin do
  alias Ippan.Token
  require Sqlite
  require BalanceStore
  require Token
  require Logger

  @max_tx_amount Application.compile_env(:ipnworker, :max_tx_amount)
  @note_max_size Application.compile_env(:ipnworker, :note_max_size)
  @token Application.compile_env(:ipnworker, :token)

  def send(source = %{id: account_id}, to, token_id, amount)
      when is_integer(amount) and amount <= @max_tx_amount and
             account_id != to do
    bt = BalanceTrace.new(source)
    fees = Tools.fees!(source, amount)

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

      Token.has_prop?(token, "coinbase") ->
        raise IppanError, "Token property invalid"

      true ->
        total =
          Enum.reduce(outputs, 0, fn [_account_id, amount], acc ->
            cond do
              amount <= 0 ->
                raise ArgumentError, "Amount must be positive number"

              amount > @max_tx_amount ->
                raise ArgumentError, "Amount exceeded max value"

              not Match.account?(account_id) ->
                raise ArgumentError, "Account ID invalid"

              true ->
                amount + acc
            end
          end)

        current_supply = TokenSupply.cache(token_id) |> TokenSupply.get()

        if current_supply + total > max_supply do
          raise IppanError, "max supply exceeded"
        end
    end
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

      "lock" not in token.props ->
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

      "lock" not in token.props ->
        raise IppanError, "Invalid property"

      true ->
        BalanceStore.requires!(dets, tx, balance_key, amount)
    end
  end

  def burn(source, token_id, amount) when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      Token.has_prop?(token, "burn") ->
        raise IppanError, "Token property invalid"

      true ->
        source
        |> BalanceTrace.new()
        |> BalanceTrace.requires!(token_id, amount)
    end
  end
end