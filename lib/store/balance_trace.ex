defmodule BalanceTrace do
  import BalanceStore, only: [multi_requires!: 3]

  defstruct db: nil, from: nil, output: %{}, tx: nil

  def new(from) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :cache_balance)
    %BalanceTrace{db: db, tx: tx, from: from}
  end

  def new(%{id: from}, db, tx) do
    %BalanceTrace{db: db, tx: tx, from: from}
  end

  def requires!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token, value) do
    key = DetsPlux.tuple(from, token)
    DetsPlux.get_cache(db, tx, key, {0, 0})

    case DetsPlux.update_counter(tx, key, {2, -value}) < 0 do
      true ->
        put_out(bt, key, value)

      false ->
        raise IppanError, "Insufficient balance"
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

  def merge_and_output(bt, bt2) do
    Map.merge(bt.output, bt2.output)
  end

  defp put_out(bm = %{output: output}, key, value) do
    %{bm | output: Map.put(output, key, value)}
  end
end
