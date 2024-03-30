defmodule MemTables do
  use GenServer
  # @set_opts [:set, :public, read_concurrency: true, write_concurrency: true]
  # @set_named_opts [:set, :named_table, :public, read_concurrency: true, write_concurrency: false]

  @ordered_options [
    :ordered_set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: false
  ]
  @set_options [
    :set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: true
  ]

  @tables %{
    hash: @set_options,
    dhash: @set_options,
    dtx: @ordered_options,
    # cache
    validator: @set_options,
    token: @set_options
  }

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(state) do
    IO.puts("init mem")
    for {table, opts} <- @tables do
      :ets.new(table, opts)
    end

    RegPay.init()

    Process.flag(:trap_exit, true)
    {:ok, state, :hibernate}
  end

  @impl true
  def terminate(_reason, _state) do
    IO.puts("terminate mem")
    for {table, _opts} <- @tables do
      :ets.delete(table)
    end

    RegPay.terminate()
  end

  def clear_cache do
    :ets.delete_all_objects(:hash)
    :ets.delete_all_objects(:dhash)
    :ets.delete_all_objects(:dtx)
  end
end
