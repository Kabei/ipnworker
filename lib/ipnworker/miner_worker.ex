defmodule MinerWorker do
  use GenServer
  import Ippan.Ecto.Tx, only: [json_type: 0]
  require RegPay
  alias Ippan.{Block, TxHandler, Validator, Wallet}
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
  @master Application.compile_env(@app, :master)

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
        :ok = Download.await(url, decode_path)
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
      e ->
        # delete player
        Validator.delete(creator_id)

        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        # IO.puts("Error occurred at #{__ENV__.file}:#{__ENV__.line}")
        {:reply, :error, state}
    after
      IO.inspect("Bstep 4")
      b = Block.to_list(block)

      Block.insert(b)
      |> IO.inspect()

      if @master do
        PgStore.insert_block(pg_conn, b)
        |> IO.inspect()
      end

      # Push event
      msg = Block.to_text(block)
      PubSub.broadcast(@pubsub, "block.new", msg)
      PubSub.broadcast(@pubsub, "block:#{block_id}", msg)
    end
  end

  defp run_miner(round_id, block_id, validator, transactions, pg_conn) do
    nonce_dets = DetsPlux.get(:nonce)
    nonce_tx = DetsPlux.tx(nonce_dets, :nonce)
    counter_ref = :counters.new(1, [])
    ets_payment = :persistent_term.get(:payment)

    Enum.each(transactions, fn
      [hash, type, from, nonce, args, size] ->
        result =
          case Wallet.update_nonce(nonce_dets, nonce_tx, from, nonce) do
            :error ->
              :error

            _number ->
              TxHandler.regular()
          end

        if @master do
          ix = :counters.get(counter_ref, 1)

          PgStore.insert_tx(pg_conn, [
            ix,
            block_id,
            hash,
            type,
            from,
            tx_status(result),
            nonce,
            size,
            json_type(),
            @json.encode!(args)
          ])
          |> IO.inspect()

          RegPay.commit_tx(pg_conn, ets_payment, hash, ix, block_id)

          :counters.add(counter_ref, 1, 1)
        end

      [hash, type, arg_key, from, nonce, args, size] ->
        result =
          case Wallet.update_nonce(nonce_dets, nonce_tx, from, nonce) do
            :error ->
              :error

            _number ->
              TxHandler.insert_deferred()
          end

        if @master do
          ix = :counters.get(counter_ref, 1)

          PgStore.insert_tx(pg_conn, [
            ix,
            block_id,
            hash,
            type,
            from,
            tx_status(result),
            nonce,
            size,
            json_type(),
            @json.encode!(args)
          ])
          |> IO.inspect()

          RegPay.commit_tx(pg_conn, ets_payment, hash, ix, block_id)

          :counters.add(counter_ref, 1, 1)
        end
    end)
  end

  defp tx_status(:error), do: 1
  defp tx_status(false), do: 1
  defp tx_status(_), do: 0
end
