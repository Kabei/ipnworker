defmodule MemTables do
  # @set_opts [:set, :public, read_concurrency: true, write_concurrency: true]
  # @set_named_opts [:set, :named_table, :public, read_concurrency: true, write_concurrency: false]

  @ordered_named_opts [
    :ordered_set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: false
  ]
  @set_named_concurrent_opts [
    :set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: true
  ]

  @tables_opt %{
    hash: @set_named_concurrent_opts,
    dhash: @set_named_concurrent_opts,
    dtx: @ordered_named_opts,
    # cache
    validator: @set_named_concurrent_opts,
    token: @set_named_concurrent_opts,
    env: @set_named_concurrent_opts
  }

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :init, [args]}
    }
  end

  def init(_args) do
    for {table, opts} <- @tables_opt do
      :ets.new(table, opts)
    end

    RegPay.init()

    :ignore
  end

  def clear_cache do
    :ets.delete_all_objects(:hash)
    :ets.delete_all_objects(:dhash)
    :ets.delete_all_objects(:dtx)
    :ets.delete_all_objects(:validator)
    :ets.delete_all_objects(:token)
    :ets.delete_all_objects(:env)
  end
end
