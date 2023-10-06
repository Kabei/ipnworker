defmodule MemTables do
  # @set_opts [:set, :public, read_concurrency: true, write_concurrency: true]
  # @set_named_opts [:set, :named_table, :public, read_concurrency: true, write_concurrency: false]

  @set_named_concurrent_opts [
    :set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: true
  ]

  @tables_name %{
    hash: "hash",
    dhash: "dhash",
    # used after process round
    dtx: "dtx",
    # cache
    validator: "validator",
    token: "token",
    env: "env"
  }

  @tables_opt %{
    hash: @set_named_concurrent_opts,
    dhash: @set_named_concurrent_opts,
    dtx: @set_named_concurrent_opts,
    # cache
    validator: @set_named_concurrent_opts,
    token: @set_named_concurrent_opts,
    env: @set_named_concurrent_opts
  }

  @tables Map.to_list(@tables_name)

  @save_extension "save"
  # @tmp_extension "save.tmp"

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

    load_all()
    :ignore
  end

  defmacrop default_dir(basename, extension) do
    quote do
      ~c"#{:persistent_term.get(:save_dir)}#{unquote(basename)}.#{unquote(extension)}"
    end
  end

  def load_all do
    for {table, name} <- @tables_name do
      :ets.file2tab(table, default_dir(name, @save_extension))
    end
  end

  def save(table) do
    name = Map.get(@tables_name, table)
    save(table, name)
  end

  def save(table, name) do
    :ets.tab2file(table, default_dir(name, @save_extension))
  end

  def save_all do
    for {table, name} <- @tables_name do
      save(table, name)
    end
  end

  def delete_all do
    for table <- @tables do
      :ets.delete(table)
    end
  end

  def clear_cache do
    :ets.delete_all_objects(:hash)
    :ets.delete_all_objects(:dhash)
    :ets.delete_all_objects(:dtx)
    :ets.delete_all_objects(:validator)
    :ets.delete_all_objects(:token)
    :ets.delete_all_objects(:env)
  end

  @spec terminate :: :ok
  def terminate do
    save_all()
    delete_all()
    :persistent_term.erase(:save_dir)
    :ok
  end
end
