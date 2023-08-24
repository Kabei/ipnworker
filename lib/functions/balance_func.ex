defmodule Ippan.Func.Balance do
  alias Ippan.Token
  require SqliteStore
  require BalanceStore

  def lock(%{id: account_id, conn: conn, stmts: stmts, dets: dets}, token_id, to_id, amount)
      when is_integer(amount) do
    token = SqliteStore.lookup_map(:token, conn, stmts, "get_token", [token_id], Token)

    cond do
      is_nil(token) ->
        raise IppanError, "TokenID not exists"

      token.owner != account_id ->
        raise IppanError, "unauthorised"

      "lock" in token.props ->
        raise IppanError, "Invalid property"

      BalanceStore.has_balance?(dets, {to_id, token_id}, amount) ->
        :ok

      true ->
        raise IppanError, "Invalid operation"
    end
  end

  def unlock(%{id: account_id, conn: conn, stmts: stmts, dets: dets}, token_id, to_id, amount)
      when is_integer(amount) do
    token = SqliteStore.lookup_map(:token, conn, stmts, "get_token", [token_id], Token)

    cond do
      is_nil(token) ->
        raise IppanError, "TokenID not exists"

      token.owner != account_id ->
        raise IppanError, "unauthorised"

      "lock" in token.props ->
        raise IppanError, "Invalid property"

      BalanceStore.can_be_unlock?(dets, {to_id, token_id}, amount) ->
        :ok

      true ->
        raise IppanError, "Invalid operation"
    end
  end
end
