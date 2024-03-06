defmodule PgStore do
  alias IO.ANSI

  # @version 0

  @creations SQL.readFile!("lib/psql/history.sql")

  @prepares SQL.readFile!("lib/psql/prepare.sql")

  @alter []

  @app Mix.Project.config()[:app]
  @json Application.compile_env(@app, :json)
  # DB Pool connections
  @pool :pg_pool
  @repo Ipnworker.Repo

  def child_spec(_args) do
    %{
      id: __MODULE__,
      restart: :permanent,
      start: {__MODULE__, :start, []},
      type: :worker
    }
  end

  defp prepare_state(pid) do
    Postgrex.transaction(
      pid,
      fn conn ->
        for sql <- @prepares do
          Postgrex.query(conn, sql, [])
        end
      end,
      timeout: :infinity
    )
  end

  cond do
    Application.compile_env(@app, :history, false) ->
      def start do
        opts = Application.get_env(@app, @repo)
        {:ok, pid} = Postgrex.start_link(opts ++ [after_connect: &prepare_state/1])
        :persistent_term.put(@pool, pid)

        init(pid, opts)
        print(opts)

        {:ok, pid}
      end

    Application.compile_env(@app, :api, true) ->
      def start do
        {:ok, pid} = Postgrex.start_link(opts)
        :persistent_term.put(@pool, pid)
        {:ok, pid}
      end

    true ->
      def start do
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
        # Restart connection
        restart(pid)

      error ->
        error
    end
  end

  def insert_tx(conn, params) do
    Postgrex.query(
      conn,
      query_parse("EXECUTE insert_tx($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)", params),
      []
    )
  end

  def insert_pay(conn, params) do
    Postgrex.query(
      conn,
      query_parse("EXECUTE insert_pay($1,$2,$3,$4,$5,$6,$7)", params),
      []
    )
  end

  def insert_block(conn, params) do
    Postgrex.query(
      conn,
      query_parse(
        "EXECUTE insert_block($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)",
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

  def upsert_balance(conn, params) do
    Postgrex.query(conn, query_parse("EXECUTE upsert_balance($1,$2,$3,$4)", params), [])
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

  # Restart service
  def restart(pid) do
    :persistent_term.erase(@pool)
    GenServer.stop(pid, :normal)
  end

  defp init(pid, opts) do
    pool_size = Keyword.get(opts, :pool_size, 1)

    Postgrex.transaction(pid, fn conn ->
      case Postgrex.query(
             conn,
             "SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = 'history');",
             []
           ) do
        {:ok, %{rows: [[false]]}} ->
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
                    # {:ok, _result} =
                    Postgrex.query(conn, sql, [])
                  end
                end,
                timeout: :infinity
              )
            end)
          end)
          |> Task.await_many(:infinity)

        _ ->
          nil
      end
    end)
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
          case Match.text?(value) do
            false ->
              bytea(value)

            true ->
              "'#{String.replace(value, "'", "''")}'"
          end

        is_map(value) ->
          "'#{String.replace(@json.encode!(value), "'", "''")}'"

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
