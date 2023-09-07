defmodule PgStore do
  alias IO.ANSI

  # @version 0

  @creations SQL.readFile!("lib/psql/history.sql")

  @alter []

  @key :pg_conn

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]}
    }
  end

  def start_link(args) do
    opts = Application.get_env(:ipnworker, :repo)
    {:ok, conn} = Postgrex.start_link(opts)
    :persistent_term.put(@key, conn)

    if List.first(args) == :init do
      init(conn)
    end

    ("Connection: " <>
       ANSI.yellow() <>
       "postgresql://#{opts[:username]}@#{opts[:hostname]}:#{opts[:port]}/#{opts[:database]}" <>
       ANSI.reset())
    |> IO.puts()

    {:ok, conn}
  end

  def init(conn) do
    # put in global conn

    for sql <- @creations do
      {:ok, _result} = Postgrex.query(conn, sql, [])
    end

    # execute alter tables if exists new version
    for sql <- @alter do
      {:ok, _result} = Postgrex.query(conn, sql, [])
    end
  end

  def get do
    :persistent_term.get(@key)
  end

  def begin(conn) do
    Postgrex.prepare_execute(conn, "BEGIN", "BEGIN", [])
  end

  def commit(conn) do
    Postgrex.prepare_execute(conn, "COMMIT", "COMMIT", [])
  end

  def sync(conn) do
    commit(conn)
    begin(conn)
  end

  def insert_event(conn, params) do
    Postgrex.prepare_execute(
      conn,
      "insert_event",
      "EXECUTE insert_event($1,$2,$3,$4,$5,$6,$7)",
      params
    )
  end

  def insert_block(conn, params) do
    Postgrex.prepare_execute(
      conn,
      "insert_block",
      "EXECUTE insert_block($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)",
      params
    )
  end

  def insert_round(conn, params) do
    Postgrex.prepare_execute(
      conn,
      "insert_round",
      "EXECUTE insert_round($1,$2,$3,$4,$5)",
      params
    )
  end

  def insert_jackpot(conn, params) do
    Postgrex.prepare_execute(
      conn,
      "insert_jackpot",
      "EXECUTE insert_jackpot($1,$2,$3)",
      params
    )
  end

  def insert_snapshot(conn, params) do
    Postgrex.prepare_execute(
      conn,
      "insert_snapshot",
      "EXECUTE insert_snapshot($1,$2,$3)",
      params
    )
  end

  def stop(conn) do
    :persistent_term.erase(@key)
    GenServer.stop(conn)
  end
end
