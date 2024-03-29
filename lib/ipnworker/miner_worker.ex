defmodule MinerWorker do
  use GenServer
  require RegPay
  alias Ippan.Utils
  alias Ippan.{Block, TxHandler, Validator, Account}
  alias Phoenix.PubSub
  require Sqlite
  require TxHandler
  require Block
  require Logger
  require Validator

  @app Mix.Project.config()[:app]
  @pubsub :pubsub
  @version Application.compile_env(@app, :version)
  @json Application.compile_env(@app, :json)
  @history Application.compile_env(@app, :history, false)
  @notify Application.compile_env(@app, :notify, false)
  @cjson Ippan.Ecto.Tx.cjson()

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, hibernate_after: 10_000)
  end

  @impl true
  def init(args) do
    {:ok, args}
  end

  def mine(server, round_id, block, hostname, creator, pg_conn) do
    GenServer.call(
      server,
      {:mine, Map.put(block, :round, round_id), hostname, creator, pg_conn},
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
            round: round_id,
            count: count,
            status: status,
            vsn: version
          } = block,
          hostname,
          creator,
          pg_conn
        },
        _from,
        state
      ) do
    db_ref = :persistent_term.get(:main_conn)

    try do
      IO.inspect("Bstep 1")
      # balances = {DetsPlux.get(:balance), DetsPlux.tx(:balance)}
      # wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}

      # Request verify a remote blockfile
      decode_path = Block.decode_path(creator_id, height)
      IO.inspect("Bstep 2")
      # Download decode-file
      if File.exists?(decode_path) do
        :ok
      else
        # Download from Cluster node
        url = Block.cluster_decode_url(hostname, creator_id, height)
        :ok = Download.from(url, decode_path, :infinity)
      end

      IO.inspect("Bstep 3")
      {:ok, content} = File.read(decode_path)

      %{"data" => txs, "vsn" => version_file} =
        Block.decode_file!(content)

      if version != version_file or version != @version,
        do: raise(IppanError, "Block file version failed")

      run_miner(round_id, block_id, creator, txs, pg_conn)

      {:reply, :ok, state}
    rescue
      err ->
        Logger.error(Exception.format(:error, err, __STACKTRACE__))

        if status > 0 do
          # delete validator
          Validator.delete(creator_id)
          PubSub.local_broadcast(:pubsub, "validator.leave", %{"id" => creator_id})
          b = Block.cancel(block, round_id, count, 1)
          :done = Block.insert(Block.to_list(b))
        end

        {:reply, :error, state}
    after
      IO.inspect("Bstep 4")
      b = Block.to_list(block)

      Block.insert(b)
      |> IO.inspect()

      if @history do
        PgStore.insert_block(pg_conn, b)
        |> then(fn
          {:ok, _} ->
            :ok

          err ->
            IO.inspect(err)
        end)
      end

      # Push event
      msg = Block.to_text(block)
      PubSub.local_broadcast(@pubsub, "block.new", msg)
      PubSub.local_broadcast(@pubsub, "block:#{block_id}", msg)
    end
  end

  defp run_miner(round_id, block_id, validator, transactions, pg_conn) do
    nonce_dets = DetsPlux.get(:nonce)
    nonce_tx = DetsPlux.tx(nonce_dets, :nonce)
    dtx = :ets.whereis(:dtx)
    dtmp = :ets.new(:tmp, [:set])
    cref = :counters.new(1, [])
    synced = :persistent_term.get(:status) == :synced

    Enum.each(transactions, fn
      ["error", hash, type, from, nonce, args, sig, size] ->
        if @history do
          ix = :counters.get(cref, 1)

          PgStore.insert_tx(pg_conn, [
            from,
            nonce,
            ix,
            block_id,
            hash,
            type,
            1,
            size,
            @cjson,
            @json.encode!(args),
            sig
          ])
        end

        if @notify and synced and type != 308 do
          PubSub.local_broadcast(@pubsub, "payments:#{from}", %{
            "hash" => Utils.encode16(hash),
            "nonce" => nonce,
            "from" => from,
            "args" => args,
            "status" => 1,
            "type" => type
          })
        end

      [hash, type, from, nonce, args, sig, size] ->
        result =
          case Account.update_nonce(nonce_dets, nonce_tx, from, nonce) do
            :error ->
              :error

            _true ->
              TxHandler.regular()
          end

        status = tx_status(result)

        if @notify and synced and type != 308 do
          PubSub.local_broadcast(@pubsub, "payments:#{from}", %{
            "hash" => Utils.encode16(hash),
            "nonce" => nonce,
            "from" => from,
            "args" => args,
            "status" => status,
            "type" => type
          })
        end

        if @history do
          ix = :counters.get(cref, 1)

          PgStore.insert_tx(pg_conn, [
            from,
            nonce,
            ix,
            block_id,
            hash,
            type,
            tx_status(result),
            size,
            @cjson,
            @json.encode!(args),
            sig
          ])

          # |> IO.inspect()
        end

        :counters.add(cref, 1, 1)

      [hash, type, arg_key, from, nonce, args, sig, size] ->
        ix = :counters.get(cref, 1)

        result =
          case Account.update_nonce(nonce_dets, nonce_tx, from, nonce) do
            :error ->
              :error

            _true ->
              TxHandler.insert_deferred(dtx, dtmp)
          end

        status = tx_status(result)

        if @notify and synced and type != 308 do
          PubSub.local_broadcast(@pubsub, "payments:#{from}", %{
            "hash" => Utils.encode16(hash),
            "nonce" => nonce,
            "from" => from,
            "args" => args,
            "status" => status,
            "type" => type
          })
        end

        if @history do
          PgStore.insert_tx(pg_conn, [
            from,
            nonce,
            ix,
            block_id,
            hash,
            type,
            status,
            size,
            @cjson,
            @json.encode!(args),
            sig
          ])

          # |> IO.inspect()
        end

        :counters.add(cref, 1, 1)
    end)
  end

  defp tx_status(:error), do: 1
  defp tx_status(false), do: 1
  defp tx_status(_), do: 0
end
