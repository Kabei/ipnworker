defmodule MinerWorker do
  use GenServer
  alias Ippan.ClusterNode
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

  def mine(server, block, creator, round_id) do
    GenServer.call(server, {:mine, block, creator, round_id}, :infinity)
  end

  def create(server, block, hostname, creator, round_id) do
    GenServer.call(server, {:create, block, hostname, creator, round_id}, :infinity)
  end

  # Create a block file from decode block file (foreign block)
  @impl true
  def handle_call(
        {
          :mine,
          %{
            id: block_id,
            creator: creator_id,
            height: height,
            count: count,
            vsn: version
          } = block,
          creator,
          current_round_id
        },
        _from,
        state
      ) do
    try do
      IO.puts("Here 0")
      conn = :persistent_term.get(:asset_conn)
      stmts = :persistent_term.get(:asset_stmt)
      dets = :persistent_term.get(:dets_balance)

      [block_height, prev_hash] =
        SqliteStore.fetch(conn, stmts, "last_block_created", [creator_id], [-1, nil])

      IO.puts("height #{height} sql-height #{block_height}")

      IO.puts(block_height)

      if height != 1 + block_height do
        raise IppanError, "Wrong block height"
      end

      # Request verify a remote blockfile
      decode_path = Block.decode_path(creator_id, height)

      IO.puts("Here 2")
      # Call verify blockfile and download decode-file
      if File.exists?(decode_path) do
        :ok
      else
        # Download from Cluster node
        block_check =
          block
          |> Map.put("hostname", creator.hostname)
          |> Map.put("pubkey", creator.pubkey)

        {node_id, node} = random_node()

        case ClusterNode.call(node_id, "verify_block", block_check, 10_000, 2) do
          {:ok, true} ->
            url = Block.cluster_decode_url(node.hostname, creator_id, height)
            :ok = Download.from(url, decode_path)

          {:ok, false} ->
            raise IppanError, "Error block verify"

          {:error, _} ->
            raise IppanError, "Error Node verify"
        end
      end

      Logger.debug("#{creator_id}.#{height} Txs: #{count} | #{decode_path} Mining...")

      IO.puts("Here 3")
      # Read decode blockfile
      {:ok, content} = File.read(decode_path)

      IO.puts("Here 4")

      %{"data" => messages, "vsn" => version_file} =
        Block.decode_file!(content)

      if version != version_file, do: raise(IppanError, "Block file version failed")

      IO.puts("Here 5")

      count_rejected =
        mine_fun(version, messages, conn, stmts, dets, creator, block_id)

      IO.puts("Here 6")

      result =
        block
        |> Map.merge(%{prev: prev_hash, round: current_round_id, rejected: count_rejected})

      IO.puts("Here 7")
      :done = SqliteStore.step(conn, stmts, "insert_block", Block.to_list(result))

      {:reply, {:ok, result}, state}
    rescue
      error ->
        Logger.error(inspect(error))
        {:reply, :error, state}
    end
  end

  def handle_call(
        {
          :create,
          %{
            id: block_id,
            creator: creator_id,
            height: height,
            vsn: version
          } = block,
          hostname,
          creator,
          _current_round_id
        },
        _from,
        state
      ) do
    try do
      IO.inspect("Bstep 1")
      conn = :persistent_term.get(:asset_conn)
      stmts = :persistent_term.get(:asset_stmt)
      dets = :persistent_term.get(:dets_balance)
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

      mine_fun(version, messages, conn, stmts, dets, pg_conn, creator, block_id)
      IO.inspect("Bstep 4")
      b = Block.to_list(block)
      x1 = SqliteStore.step(conn, stmts, "insert_block", b)
      x2 = PgStore.insert_block(pg_conn, b)
      IO.inspect(x1)
      IO.inspect(x2)

      {:reply, :ok, state}
    rescue
      error ->
        Logger.error(inspect(error))
        {:reply, :error, state}
    end
  end

  # Process the block
  defp mine_fun(@version, messages, conn, stmts, dets, pg_conn, validator, block_id) do
    creator_id = validator.id

    Enum.reduce(messages, 0, fn
      [hash, type, from, args, timestamp, size], acc ->
        case TxHandler.handle_regular(
               conn,
               stmts,
               dets,
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
                nil,
                CBOR.encode(args)
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

  defp mine_fun(version, _messages, _conn, _stmts, _dets, _creator_id, _block_id) do
    raise IppanError, "Error block version #{inspect(version)}"
  end

  defp random_node do
    case ClusterNode.get_random_node() do
      nil ->
        :timer.sleep(1_000)
        random_node()

      result ->
        result
    end
  end
end
