defmodule PgStore do
  alias IO.ANSI

  # @version 0

  @creations SQL.readFile!("lib/psql/history.sql")

  @prepares SQL.readFile!("lib/psql/prepare.sql")

  @alter []

  @app :ipnworker
  # DB Pool connexions
  @pool :pg_pool
  @repo Ipnworker.Repo

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, []}
    }
  end

  def start do
    case :persistent_term.get(:mow) do
      true ->
        opts =
          Application.get_env(@app, @repo)
          |> then(fn opts ->
            writers = Keyword.get(opts, :wsize, 1)
            Keyword.put(opts, :pool_size, writers)
          end)

        {:ok, pid} = Postgrex.start_link(opts)
        :persistent_term.put(@pool, pid)

        init(pid, opts)
        print(opts)

        {:ok, pid}

      false ->
        :ignore
    end
  end

  def pool do
    :persistent_term.get(@pool, nil)
  end

  def reset do
    pid = pool()

    # Destroy all data
    case Postgrex.query(pid, "DROP SCHEMA history CASCADE;", []) do
      {:ok, _} ->
        # Stop connection
        stop(pid)
        # Init connection
        pid = start()
        pid

      error ->
        error
    end
  end

  def insert_txs(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE insert_txs($1,$2,$3,$4,$5,$6,$7,$8)", params), [])
  end

  def insert_block(conn, params) do
    Postgrex.query(
      conn,
      query_parse(
        "EXECUTE insert_block($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
        params
      ),
      []
    )
  end

  def insert_round(conn, params) do
    Postgrex.query(
      conn,
      query_parse("EXECUTE insert_round($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)", params),
      []
    )
  end

  def insert_balance(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE insert_balance($1,$2,$3,$4)", params), [])
  end

  def insert_jackpot(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE insert_jackpot($1,$2,$3)", params), [])
  end

  def insert_snapshot(conn, params) do
    Postgrex.query(
      conn,
      query_parse(
        "EXECUTE insert_snapshot($1,$2,$3)",
        params
      ),
      []
    )
  end

  def stop(pid) do
    :persistent_term.erase(@pool)
    GenServer.stop(pid)
  end

  defp init(pid, opts) do
    pool_size = Keyword.get(opts, :pool_size, 1)

    Postgrex.transaction(
      pid,
      fn conn ->
        # Create initial data if not exists and prepared statements
        for sql <- @creations do
          {:ok, _result} = Postgrex.query(conn, sql, [])
        end

        # Execute alter tables if exists new version
        for sql <- @alter do
          {:ok, _result} = Postgrex.query(conn, sql, [])
        end
      end,
      timeout: :infinity
    )

    # Prepare statements
    Enum.map(1..pool_size, fn _ ->
      Task.async(fn ->
        Postgrex.transaction(
          pid,
          fn conn ->
            for sql <- @prepares do
              {:ok, _result} = Postgrex.query(conn, sql, [])
            end
          end,
          timeout: :infinity
        )
      end)
    end)
    |> Task.await_many(:infinity)
  end

  defmacro text?(value) do
    quote location: :keep do
      Regex.match?(~r/^[\x20-\x26|\x28-\x7E]+$/, unquote(value))
    end
  end

  defmacro bytea(x) do
    quote location: :keep do
      "decode('#{Fast64.encode64(unquote(x))}','base64')"
    end
  end

  defmacro type_parse(value) do
    quote bind_quoted: [value: value], location: :keep do
      cond do
        is_nil(value) ->
          "NULL"

        is_binary(value) ->
          case text?(value) do
            false ->
              bytea(value)

            true ->
              "'#{String.replace(value, "'", "''")}'"
          end

        true ->
          "#{value}"
      end
    end
  end

  defp query_parse(query, params) do
    for {value, n} <- Enum.with_index(params), reduce: query do
      acc ->
        String.replace(acc, ~r/\$#{n + 1}\b/, type_parse(value))
    end
  end

  defp print(opts) do
    ("Connection: " <>
       ANSI.yellow() <>
       "postgresql://#{opts[:username]}@#{opts[:hostname]}:#{opts[:port]}/#{opts[:database]}" <>
       ANSI.reset())
    |> IO.puts()
  end
end
