defmodule MinerWorker do
  use GenServer
  alias Phoenix.PubSub
  alias Ippan.TxHandler
  alias Ippan.Wallet
  alias Ippan.Block
  require SqliteStore
  require TxHandler
  require Logger

  @version Application.compile_env(:ipnworker, :version)
  @pubsub :cluster

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
            vsn: version
          } = block,
          hostname,
          creator,
          pg_conn
        },
        _from,
        state
      ) do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    writer = pg_conn != nil

    try do
      # IO.inspect("Bstep 1")
      balances = {DetsPlux.get(:balance), DetsPlux.tx(:balance)}
      wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}

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

      %{"data" => messages, "vsn" => version_file} =
        Block.decode_file!(content)

      if version != version_file, do: raise(IppanError, "Block file version failed")

      if writer do
        mine_fun(version, messages, conn, stmts, balances, wallets, creator, block_id, pg_conn)
      else
        mine_fun(version, messages, conn, stmts, balances, wallets, creator, block_id)
      end

      # IO.inspect("Bstep 4")
      b = Block.to_list(block)
      SqliteStore.step(conn, stmts, "insert_block", b)
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
        SqliteStore.step(conn, stmts, "delete_validator", [creator_id])

        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        # IO.puts("Error occurred at #{__ENV__.file}:#{__ENV__.line}")
        {:reply, :error, state}
    end
  end

  defp mine_fun(
         @version,
         messages,
         conn,
         stmts,
         balances,
         {wallet_dets, _wallet_tx} = wallets,
         validator,
         block_id
       ) do
    creator_id = validator.id

    nonce_tx = DetsPlux.tx(wallet_dets, :nonce)

    Enum.reduce(messages, 0, fn
      [hash, type, from, args, timestamp, nonce, size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
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
        end

      msg = [_hash, _type, _arg_key, from, _args, _timestamp, nonce, _size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
            case TxHandler.insert_deferred(msg, creator_id, block_id) do
              true ->
                acc

              false ->
                acc + 1
            end
        end
    end)
  end

  defp mine_fun(version, _messages, _conn, _stmts, _balances, _wallets, _validator, _block_id) do
    raise IppanError, "Error block version #{inspect(version)}"
  end

  # Process the block
  defp mine_fun(
         @version,
         messages,
         conn,
         stmts,
         balances,
         {wallet_dets, _wallet_tx} = wallets,
         validator,
         block_id,
         pg_conn
       ) do
    creator_id = validator.id

    nonce_tx = DetsPlux.tx(wallet_dets, :nonce)

    Enum.reduce(messages, 0, fn
      [hash, type, from, args, timestamp, nonce, size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
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

                # |> IO.inspect()
                acc
            end
        end

      msg = [hash, type, _arg_key, from, args, timestamp, nonce, _size], acc ->
        case Wallet.update_nonce(wallet_dets, nonce_tx, from, nonce) do
          :error ->
            acc + 1

          _number ->
            case TxHandler.insert_deferred(msg, creator_id, block_id) do
              true ->
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

                # |> IO.inspect()

                acc

              false ->
                acc + 1
            end
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
