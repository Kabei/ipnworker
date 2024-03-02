defmodule BalanceTrace do
  import BalanceStore, only: [multi_requires!: 3]

  defstruct db: nil, from: nil, output: [], tx: nil

  def new(from, tx_name) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, tx_name)
    %BalanceTrace{db: db, tx: tx, from: from}
  end

  def auth!(bt, _token, false), do: bt

  def auth!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token, _check) do
    key = DetsPlux.tuple(from, token)
    {_, map} = DetsPlux.get_cache(db, tx, key, {0, %{}})

    if Map.get(map, "auth", false) == false,
      do: raise(IppanError, "Account balance unauthorized")

    bt
  end

  def requires!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token, value) do
    key = DetsPlux.tuple(from, token)
    DetsPlux.get_cache(db, tx, key, {0, %{}})

    if DetsPlux.update_counter(tx, key, {2, -value}) < 0 do
      DetsPlux.update_counter(tx, key, {2, value})
      raise IppanError, "Insufficient balance"
    else
      put_out(bt, key, value)
    end
  end

  def multi_requires!(
        bt = %BalanceTrace{db: db, from: from, output: outputs, tx: tx},
        token_value_list
      ) do
    kw =
      Enum.reduce(token_value_list, [], fn {token, value}, acc ->
        key = DetsPlux.tuple(from, token)

        [{key, value} | acc]
      end)

    multi_requires!(db, tx, kw)
    %{bt | output: :lists.merge(kw, outputs)}
  end

  def can_unlock!(bt = %BalanceTrace{db: db, from: from, tx: tx}, token, amount) do
    key = DetsPlux.tuple(from, token)
    {_, map} = DetsPlux.get_cache(db, tx, key, {0, %{}})

    if Map.get(map, "lock", 0) < amount do
      raise IppanError, "Invalid unlock amount"
    end

    bt
  end

  def output(%BalanceTrace{output: output}) do
    %{output: output}
  end

  defp put_out(bm = %{output: output}, key, value) do
    %{bm | output: [{key, value} | output]}
  end
end
