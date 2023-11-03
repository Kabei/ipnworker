defmodule BalanceTrace do
  import BalanceStore, only: [multi_requires!: 3]

  defstruct db: nil, from: nil, output: [], tx: nil

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

    if DetsPlux.update_counter(tx, key, {2, -value}) < 0 do
      raise IppanError, "Insufficient balance"
    else
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
    %{output: output}
  end

  defp put_out(bm = %{output: output}, key, value) do
    %{bm | output: [{key, value} | output]}
  end
end
