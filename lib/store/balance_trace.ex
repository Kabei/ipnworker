defmodule BalanceTrace do
  import BalanceStore, only: [multi_requires!: 3]

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

  def multi_requires!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token_value_list) do
    {bt, key_value_list} =
      Enum.reduce(token_value_list, {bt, []}, fn {token, value}, {bt, key_values} ->
        key = DetsPlux.tuple(from, token)
        {put_out(bt, key, value), [{key, value} | key_values]}
      end)

    multi_requires!(db, tx, key_value_list)
    bt
  end

  def output(%BalanceTrace{output: output}) do
    output
  end

  defp put_out(bm = %{output: output}, key, value) do
    %{bm | output: Map.put(output, key, value)}
  end
end