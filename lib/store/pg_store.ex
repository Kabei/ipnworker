defmodule PgStore do
  alias IO.ANSI

  # @version 0

  @creations SQL.readFile!("lib/psql/history.sql")

  @alter []

  @app :ipnworker
  @key :pg_conn

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :init, [args]}
    }
  end

  def init(args) do
    conn = conn()

    if args == [:init] do
      for sql <- @creations do
        {:ok, _result} = Postgrex.query(conn, sql, [])
      end

      # execute alter tables if exists new version
      for sql <- @alter do
        {:ok, _result} = Postgrex.query(conn, sql, [])
      end
    end

    opts = Application.get_env(@app, :repo)

    ("Connection: " <>
       ANSI.yellow() <>
       "postgresql://#{opts[:username]}@#{opts[:hostname]}:#{opts[:port]}/#{opts[:database]}" <>
       ANSI.reset())
    |> IO.puts()

    :ignore
  end

  def conn do
    case :persistent_term.get(@key, nil) do
      nil ->
        opts = Application.get_env(@app, :repo)
        {:ok, conn} = Postgrex.start_link(opts)
        :persistent_term.put(@key, conn)
        conn

      conn ->
        conn
    end
  end

  def reset(conn) do
    {:ok, _result} = Postgrex.query(conn, "DROP SCHEMA history CASCADE;", [])

    # stop connection
    stop(conn)
    # init connection
    conn = conn()

    for sql <- @creations do
      {:ok, _result} = Postgrex.query(conn, sql, [])
    end

    conn
  end

  def begin(conn) do
    Postgrex.query(conn, "BEGIN;", [])
  end

  def commit(conn) do
    case Postgrex.query(conn, "COMMIT;", []) do
      {:ok, _} = r ->
        r

      error ->
        Postgrex.query(conn, "ABORT;", [])
        error
    end
  end

  def rollback(conn) do
    Postgrex.query(conn, "ROLLBACK;", [])
  end

  def insert_event(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE insert_event($1,$2,$3,$4,$5,$6,$7,$8)", params), [])
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
      query_parse("EXECUTE insert_round($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)", params),
      []
    )
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

  def stop(conn) do
    :persistent_term.erase(@key)
    GenServer.stop(conn)
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
end
