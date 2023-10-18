defmodule BalanceTrace do
  defstruct db: nil, from: nil, output: %{}, tx: nil

  def new(%{id: from}) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :cache_balance)
    %BalanceTrace{db: db, tx: tx, from: from}
  end

  def new(%{id: from}, db, tx) do
    %BalanceTrace{db: db, tx: tx, from: from}
  end

  def requires!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token, value) do
    key = DetsPlux.tuple(from, token)
    {balance, _lock} = DetsPlux.get_tx(db, tx, key, {0, 0})
    result = balance - value

    case result > 0 do
      false ->
        raise IppanError, "Insufficient balance"

      true ->
        DetsPlux.put(tx, key, result)
        put_out(bt, key, value)
    end
  end

  def output(%BalanceTrace{output: output}) do
    output
  end

  defp put_out(bm = %{output: output}, key, value) do
    %{bm | output: Map.put(output, key, value)}
  end
end
