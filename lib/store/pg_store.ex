defmodule PgStore do
  alias IO.ANSI

  # @version 0

  @creations SQL.readFile!("lib/psql/history.sql")

  @alter []

  @key :pg_conn

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :init, [args]}
    }
  end

  def init(args) do
    opts = Application.get_env(:ipnworker, :repo)
    {:ok, conn} = Postgrex.start_link(opts)
    :persistent_term.put(@key, conn)

    case args do
      [:init] ->
        for sql <- @creations do
          {:ok, _result} = Postgrex.query(conn, sql, [])
        end

        # execute alter tables if exists new version
        for sql <- @alter do
          {:ok, _result} = Postgrex.query(conn, sql, [])
        end

      _ ->
        nil
    end

    ("Connection: " <>
       ANSI.yellow() <>
       "postgresql://#{opts[:username]}@#{opts[:hostname]}:#{opts[:port]}/#{opts[:database]}" <>
       ANSI.reset())
    |> IO.puts()

    :ignore
  end

  def conn do
    :persistent_term.get(@key)
  end

  def begin(conn) do
    Postgrex.prepare_execute(conn, "", "BEGIN", [])
  end

  def commit(conn) do
    Postgrex.prepare_execute(conn, "", "COMMIT", [])
  end

  def sync(conn) do
    commit(conn)
    begin(conn)
  end

  def insert_event(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE insert_event($1,$2,$3,$4,$5,$6,$7)", params), [])
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
      query_parse("EXECUTE insert_round($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)", params),
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
      "decode('#{Fast64.encode64(unquote(x))}', 'base64')"
    end
  end

  defmacro type_parse(value) do
    quote bind_quoted: [value: value], location: :keep do
      cond do
        is_binary(value) ->
          case text?(value) do
            false ->
              bytea(value)

            true ->
              String.replace(value, "'", "''")
          end

        true ->
          "#{value}"
      end
    end
  end

  defp query_parse(query, params) do
    for {value, n} <- Enum.with_index(params), reduce: query do
      acc ->
        p = "$#{n + 1}"

        String.replace(acc, p, type_parse(value))
    end
  end
end
