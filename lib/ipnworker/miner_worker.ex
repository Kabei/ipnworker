defmodule MinerWorker do
  use GenServer
  alias Ippan.{Block, TxHandler, Validator, Wallet}
  alias Phoenix.PubSub
  require Sqlite
  require TxHandler
  require Block
  require Logger
  require Validator

  @pubsub :pubsub
  @version Application.compile_env(:ipnworker, :version)
  @json Application.compile_env(:ipnworker, :json)

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
    writer = pg_conn != nil

    try do
      # IO.inspect("Bstep 1")
      # balances = {DetsPlux.get(:balance), DetsPlux.tx(:balance)}
      # wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}
      wallet_dets = DetsPlux.get(:wallet)

      # Request verify a remote blockfile
      decode_path = Block.decode_path(creator_id, height)
      # IO.inspect("Bstep 2")
      # Download decode-file
      if File.exists?(decode_path) do
        :ok
      else
        # Download from Cluster node
        url = Block.cluster_decode_url(hostname, creator_id, height)
        :ok = Download.await(url, decode_path)
      end

      # IO.inspect("Bstep 3")
      {:ok, content} = File.read(decode_path)

      %{"data" => txs, "vsn" => version_file} =
        Block.decode_file!(content)

      if version != version_file or version != @version,
        do: raise(IppanError, "Block file version failed")

      run_miner(round_id, block_id, creator, txs, wallet_dets, pg_conn, writer)

      # IO.inspect("Bstep 4")
      b = Block.to_list(block)
      Block.insert(b)
      # |> IO.inspect(x1)

      if writer do
        PgStore.insert_block(pg_conn, b)
        # |> IO.inspect()
      end

      # Push event
      PubSub.broadcast(@pubsub, "block.new", block)

      {:reply, :ok, state}
    rescue
      e ->
        # delete player
        Validator.delete(creator_id)

        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        # IO.puts("Error occurred at #{__ENV__.file}:#{__ENV__.line}")
        {:reply, :error, state}
    end
  end

  defp run_miner(round_id, block_id, validator, transactions, wallet_dets, pg_conn, writer) do
    nonce_tx = DetsPlux.tx(wallet_dets, :nonce)

    Enum.each(transactions, fn
      [hash, type, from, nonce, args, size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
            TxHandler.regular()

            if writer do
              PgStore.insert_event(pg_conn, [
                block_id,
                hash,
                type,
                from,
                nonce,
                size,
                @json.encode!(args)
              ])
            end
        end

      body = [hash, type, arg_key, from, nonce, args, size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
            TxHandler.insert_deferred()

            if writer do
              PgStore.insert_event(pg_conn, [
                block_id,
                hash,
                type,
                from,
                nonce,
                size,
                @json.encode!(args)
              ])
            end
        end
    end)
  end
end
