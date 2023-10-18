defmodule Ippan.Func.Balance do
  alias Ippan.Token
  require BalanceStore
  require Sqlite
  require Token

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
end
