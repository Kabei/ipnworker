defmodule Ippan.Func.Tx do
  alias Ippan.Token
  require SqliteStore
  require BalanceStore
  require Token
  require Logger

  @max_tx_amount Application.compile_env(:ipnworker, :max_tx_amount)
  @note_max_size Application.compile_env(:ipnworker, :note_max_size)
  @token Application.compile_env(:ipnworker, :token)

  def send(_, token, outputs)
      when byte_size(token) <= 10 and is_list(outputs) do
    raise IppanError, "multisend no supported yet"
  end

  def send(
        source = %{id: account_id},
        to,
        token_id,
        amount,
        note \\ <<>>
      )
      when is_integer(amount) and amount <= @max_tx_amount and
             account_id != to and
             byte_size(note) <= @note_max_size do
    bt = BalanceTrace.new(source)
    fees = Tools.fees!(source, amount)

    case token_id == @token do
      true ->
        BalanceTrace.requires!(bt, token_id, amount + fees)

      false ->
        bt
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.requires!(@token, fees)
    end
    |> BalanceTrace.output()
  end

  # with refund enabled
  def send_refundable(source, to, token, amount) do
    send(source, to, token, amount)
  end

  def coinbase(%{id: account_id, conn: conn, stmts: stmts}, token_id, outputs)
      when length(outputs) > 0 do
    %{max_supply: max_supply} =
      token = SqliteStore.lookup_map(:token, conn, stmts, "get_token", [token_id], Token)

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

  def burn(source, token_id, amount) when is_integer(amount) and amount > 0 do
    conn = :persistent_term.get(:asset_conn)
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

  def refund(%{id: account_id, conn: conn, stmts: stmts, timestamp: timestamp}, hash16)
      when byte_size(hash16) == 64 do
    hash = Base.decode16!(hash16, case: :mixed)

    case SqliteStore.exists?(conn, stmts, "exists_refund", [hash, account_id, timestamp]) do
      false ->
        raise IppanError, "Hash refund not exists"

      true ->
        :ok
    end
  end
end
