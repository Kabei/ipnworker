defmodule MinerWorker do
  use GenServer
  alias Ippan.TxHandler
  alias Ippan.Block
  require SqliteStore
  require TxHandler
  require Logger

  @version Application.compile_env(:ipnworker, :version)

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, hibernate_after: 10_000)
  end

  @impl true
  def init(args) do
    {:ok, args}
  end

  def mine(server, round_id, block, hostname, creator, mow) do
    GenServer.call(
      server,
      {:mine, Map.put(block, :round, round_id), hostname, creator, mow},
      :infinity
    )
  end

  @impl true
  def handle_call(
        {
          :mine,
          %{
            id: block_id,
            creator: creator_id,
            height: height,
            vsn: version
          } = block,
          hostname,
          creator,
          mow
        },
        _from,
        state
      ) do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)

    try do
      IO.inspect("Bstep 1")
      balances = {DetsPlux.get(:balance), DetsPlux.tx(:balance)}
      wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}
      pg_conn = PgStore.conn()

      # Request verify a remote blockfile
      decode_path = Block.decode_path(creator_id, height)
      IO.inspect("Bstep 2")
      # Download decode-file
      if File.exists?(decode_path) do
        :ok
      else
        # Download from Cluster node
        url = Block.cluster_decode_url(hostname, creator_id, height)
        :ok = Download.await(url, decode_path)
      end

      IO.inspect("Bstep 3")
      {:ok, content} = File.read(decode_path)

      %{"data" => messages, "vsn" => version_file} =
        Block.decode_file!(content)

      if version != version_file, do: raise(IppanError, "Block file version failed")

      if mow do
        mine_fun(version, messages, conn, stmts, balances, wallets, creator, block_id, pg_conn)
      else
        mine_fun(version, messages, conn, stmts, balances, wallets, creator, block_id)
      end

      IO.inspect("Bstep 4")
      b = Block.to_list(block)
      x1 = SqliteStore.step(conn, stmts, "insert_block", b)

      if mow do
        x2 = PgStore.insert_block(pg_conn, b)
        IO.inspect(x2)
      end

      IO.inspect(x1)

      {:reply, :ok, state}
    rescue
      error ->
        # delete player
        SqliteStore.step(conn, stmts, "delete_validator", [creator_id])

        Logger.error(inspect(error))
        {:reply, :error, state}
    end
  end

  defp mine_fun(@version, messages, conn, stmts, balances, wallets, validator, block_id) do
    creator_id = validator.id

    Enum.reduce(messages, 0, fn
      [hash, type, from, args, timestamp, size], acc ->
        case TxHandler.handle_regular(
               conn,
               stmts,
               balances,
               wallets,
               validator,
               hash,
               type,
               from,
               args,
               size,
               timestamp,
               block_id
             ) do
          :error -> acc + 1
          _ -> acc
        end

      msg, acc ->
        case TxHandler.insert_deferred(msg, creator_id, block_id) do
          true ->
            acc

          false ->
            acc + 1
        end
    end)
  end

  defp mine_fun(version, _messages, _conn, _stmts, _balances, _wallets, _validator, _block_id) do
    raise IppanError, "Error block version #{inspect(version)}"
  end

  # Process the block
  defp mine_fun(@version, messages, conn, stmts, balances, wallets, validator, block_id, pg_conn) do
    creator_id = validator.id

    Enum.reduce(messages, 0, fn
      [hash, type, from, args, timestamp, nonce, size], acc ->
        case TxHandler.handle_regular(
               conn,
               stmts,
               balances,
               wallets,
               validator,
               hash,
               type,
               from,
               args,
               size,
               timestamp,
               block_id
             ) do
          :error ->
            acc + 1

          _ ->
            r =
              PgStore.insert_event(pg_conn, [
                block_id,
                hash,
                type,
                from,
                timestamp,
                nonce,
                nil,
                Jason.encode!(args)
              ])

            IO.inspect(r)
            acc
        end

      msg, acc ->
        case TxHandler.insert_deferred(msg, creator_id, block_id) do
          true ->
            acc

          false ->
            acc + 1
        end
    end)
  end

  defp mine_fun(
         version,
         _messages,
         _conn,
         _stmts,
         _balances,
         _wallets,
         _validator,
         _block_id,
         _pg_conn
       ) do
    raise IppanError, "Error block version #{inspect(version)}"
  end
end
