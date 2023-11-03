defmodule TokenSupply do
  require DetsPlux
  @db :stats
  @tx :supply
  @cache_tx :cache_supply
  @word "supply"

  defstruct db: nil, id: nil, tx: nil, key: nil, output: []

  defmacrop key(token_id) do
    quote do
      DetsPlux.tuple(unquote(token_id), @word)
    end
  end

  def new(id) do
    db = DetsPlux.get(@db)
    tx = DetsPlux.tx(db, @tx)
    key = key(id)
    DetsPlux.get_cache(db, tx, key, 0)

    %__MODULE__{
      id: id,
      db: db,
      tx: tx,
      key: key
    }
  end

  def cache(id) do
    db = DetsPlux.get(@db)
    tx = DetsPlux.tx(db, @cache_tx)
    key = key(id)
    DetsPlux.get_cache(db, tx, key, 0)

    %__MODULE__{
      db: db,
      tx: tx,
      key: key
    }
  end

  def get(%{db: db, tx: tx, key: key}) do
    DetsPlux.get_tx(db, tx, key, 0)
  end

  @spec get(DetsPlux.db(), DetsPlux.transaction(), binary) :: supply :: integer()
  def get(db, tx, key) do
    DetsPlux.get_cache(db, tx, key, 0)
  end

  @spec put(map, integer()) :: true
  def put(%{tx: tx, key: key}, amount) do
    DetsPlux.put(tx, key, amount)
  end

  @spec add(map, number()) :: number()
  def add(%{tx: tx, key: key}, amount) do
    DetsPlux.update_counter(tx, key, amount)
  end

  @spec subtract(map, number()) :: number()
  def subtract(%{tx: tx, key: key}, amount) do
    DetsPlux.update_counter(tx, key, -amount)
  end

  @spec requires!(map, number(), number()) :: :ok | no_return()
  def requires!(ts = %{tx: tx, key: key}, amount, max_supply) do
    if DetsPlux.update_counter(tx, key, amount) > max_supply do
      DetsPlux.update_counter(tx, key, -amount)
      raise IppanError, "max supply exceeded"
    else
      put_out(ts, amount, max_supply)
    end
  end

  def multi_requires!(outputs) do
    db = DetsPlux.get(@db)
    tx = DetsPlux.tx(db, @cache_tx)

    Enum.reduce(outputs, [], fn {key, amount, max_supply}, acc ->
      if DetsPlux.update_counter(tx, key, amount) > max_supply do
        DetsPlux.update_counter(tx, key, -amount)
        raise IppanError, "max supply exceeded"
      else
        [{key, amount} | acc]
      end
    end)
    |> Enum.each(fn {key, amount} ->
      DetsPlux.update_counter(tx, key, -amount)
    end)
  end

  @spec delete(map) :: true
  def delete(%{tx: tx, key: key}) do
    DetsPlux.delete(tx, key)
  end

  def output(%TokenSupply{output: output}) do
    output
  end

  defp put_out(ts = %{key: key, output: output}, value, max_supply) do
    %{ts | output: [{key, value, max_supply} | output]}
  end
end
