defmodule Ipncore.MinerWorker do
  alias Ippan.{DetsSup, ClusterNodes}
  alias Ippan.Block
  alias Ippan.TxHandler
  alias Ippan.Funcs
  alias Ippan.Validator

  @download_cluster_options [retry: :infinity, time_to_retry: 100]
  # @download_options [retry: 5, time_to_retry: 250]

  def build(_round_id, [], _verify) do
    %{rejected: 0}
  end

  def build(round_id, blocks, verify) do
    cref = :counters.new(2, [])
    txd = :ets.new(:txd, [:duplicate_bag, :public])
    workers = TxWorker.all()

    refs = %{
      db_ref: :persistent_term.get(:main_conn),
      cref: cref,
      dets: DetsSup.dets(),
      txs: DetsSup.txs(),
      txd: txd,
      verify: verify,
      workers: workers,
      error: :ets.new(:error, [:duplicate_bag, :public])
    }

    do_mine(round_id, refs, blocks)
    do_run_deferred(txd, workers)

    # Wait for all workers to finish
    workers
    |> Enum.each(fn {_num, worker} ->
      :gen_server.call(worker, :done, :infinity)
    end)

    %{
      rejected: :counters.get(cref, 2)
    }
  end

  defp do_mine(_round_id, _refs, []), do: :ok

  defp do_mine(round_id, refs, [block | blocks]) do
    mine(round_id, block, refs)
    do_mine(round_id, refs, blocks)
  end

  @partitions TxSupervisor.partitions()
  defp mine(
         round_id,
         block = %{
           creator: creator_id,
           height: height
         },
         %{
           db_ref: db_ref,
           cref: cref,
           error: _ets_error,
           txd: txd,
           verify: verify,
           workers: workers
         } = _refs
       ) do
    decode_path = Block.decode_path(creator_id, height)
    creator = Validator.get(db_ref, creator_id)

    {ptxs, errors} = get_transactions(creator, round_id, decode_path, block, verify)
    :counters.add(cref, 2, errors)

    Enum.each(ptxs, fn
      {"d", txs} ->
        :ets.insert(txd, txs)

      {_number, txs} ->
        Enum.each(
          txs,
          fn tx = {_hash, type_id, from, _nonce, args, _size, _signature} ->
            type = %{flag: flag} = Funcs.lookup(type_id)
            pnum = TxHandler.get_part(flag, from, args, @partitions)
            worker = Map.get(workers, pnum)

            # send transaction to process
            :gen_server.cast(worker, {:run, tx, type})
          end
        )
    end)
  end

  defp do_run_deferred(tid, workers) do
    do_run_deferred(:ets.first(tid), tid, workers)
  end

  defp do_run_deferred(:"$end_of_table", _tid, _pids), do: :ok

  defp do_run_deferred(key, tid, pids) do
    [tx = {_hash, type_id, from, _nonce, args, _size, _signature}] = :ets.lookup(tid, key)
    type = %{flag: flag} = Funcs.lookup(type_id)
    pnum = TxHandler.get_part(flag, from, args, @partitions)
    pid = Map.get(pids, pnum)
    :gen_server.cast(pid, {:run, tx, type})

    do_run_deferred(:ets.next(tid, key), tid, pids)
  end

  defp get_transactions(creator, round_id, output_path, block, verify) do
    # Get or/and Verify blockfile
    cond do
      File.exists?(output_path) ->
        # do not download
        :ok

      verify == false ->
        # download block from remote node
        url = Block.decode_url(creator.hostname, creator.id, block.height)
        :ok = DownloadTask.start(url, output_path, @download_cluster_options)

      true ->
        block =
          block
          |> Map.put("hostname", creator.hostname)
          |> Map.put("round", round_id)

        # verify block
        case random_node_verify(block) do
          {:ok, node} ->
            # download block from cluster
            url = Block.cluster_decode_url(node.hostname, creator.id, block.height)
            :ok = DownloadTask.start(url, output_path, @download_cluster_options)

          :error ->
            {:error, "Error block verify"}
        end
    end

    {:ok, content} = File.read(output_path)
    {:ok, %{"txs" => transactions, "errors" => errors}, _} = CBOR.decode(content)
    {transactions, errors}
  end

  defp random_node_verify(block) do
    IO.inspect("random_node_verify")

    case ClusterNodes.get_random_node() do
      nil ->
        IO.inspect("random_node_verify: nil")
        :timer.sleep(200)
        random_node_verify(block)

      {node_id, node} ->
        case ClusterNodes.call(node_id, "verify_block", block,
               timeout: 10_000,
               retry: 1
             ) do
          {:ok, 1} ->
            IO.inspect("random_node_verify Call 1")
            {:ok, node}

          {:ok, 0} ->
            IO.inspect("random_node_verify Call 0")
            :error

          {:ok, 2} ->
            IO.inspect("random_node_verify Call 2")
            :timer.sleep(500)
            random_node_verify(block)

          {:error, _} ->
            IO.inspect("random_node_verify Call ERROR")
            :timer.sleep(500)
            random_node_verify(block)
        end
    end
  end
end

# defmodule MinerWorker do
#   use GenServer
#   require RegPay
#   alias Ippan.Utils
#   alias Ippan.{Block, TxHandler, Validator, Account}
#   alias Phoenix.PubSub
#   require TxHandler
#   require Logger

#   @app Mix.Project.config()[:app]
#   @pubsub :pubsub
#   @version Application.compile_env(@app, :version)
#   @json Application.compile_env(@app, :json)
#   @history Application.compile_env(@app, :history, false)
#   @notify Application.compile_env(@app, :notify, false)
#   @cjson Ippan.Ecto.Tx.cjson()

#   def start_link(_) do
#     GenServer.start_link(__MODULE__, nil, hibernate_after: 10_000)
#   end

#   @impl true
#   def init(args) do
#     {:ok, args}
#   end

#   def mine(server, round_id, block, hostname, creator, pg_conn) do
#     GenServer.call(
#       server,
#       {:mine, Map.put(block, :round, round_id), hostname, creator, pg_conn},
#       :infinity
#     )
#   end

#   @impl true
#   def handle_call(
#         {
#           :mine,
#           %{
#             id: block_id,
#             creator: creator_id,
#             height: height,
#             round: round_id,
#             count: count,
#             status: status,
#             vsn: version
#           } = block,
#           hostname,
#           creator,
#           pg_conn
#         },
#         _from,
#         state
#       ) do
#     db_ref = :persistent_term.get(:main_conn)

#     try do
#       IO.inspect("Bstep 1")
#       # balances = {DetsPlux.get(:balance), DetsPlux.tx(:balance)}
#       # wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}

#       # Request verify a remote blockfile
#       decode_path = Block.decode_path(creator_id, height)
#       IO.inspect("Bstep 2")
#       # Download decode-file
#       if File.exists?(decode_path) do
#         :ok
#       else
#         # Download from Cluster node
#         url = Block.cluster_decode_url(hostname, creator_id, height)
#         :ok = Download.from(url, decode_path, retry: :infinity, time_to_retry: 100)
#       end

#       IO.inspect("Bstep 3")
#       {:ok, content} = File.read(decode_path)

#       %{"data" => txs, "vsn" => version_file} =
#         Block.decode_file!(content)

#       if version != version_file or version != @version,
#         do: raise(IppanError, "Block file version failed")

#       run_miner(round_id, block_id, creator, txs, pg_conn)

#       {:reply, :ok, state}
#     rescue
#       err ->
#         Logger.error(Exception.format(:error, err, __STACKTRACE__))

#         if status > 0 do
#           # delete validator
#           Validator.delete(db_ref, creator_id)
#           PubSub.local_broadcast(:pubsub, "validator.leave", %{"id" => creator_id})
#           b = Block.cancel(block, round_id, count, 1)
#           :done = Block.insert(db_ref, b)
#         end

#         {:reply, :error, state}
#     after
#       IO.inspect("Bstep 4")
#       b = Block.to_list(block)

#       Block.insert(db_ref, b)
#       |> IO.inspect()

#       if @history do
#         PgStore.insert_block(pg_conn, b)
#         |> then(fn
#           {:ok, _} ->
#             :ok

#           err ->
#             IO.inspect(err)
#         end)
#       end

#       # Push event
#       msg = Block.to_text(block)
#       PubSub.local_broadcast(@pubsub, "block.new", msg)
#       PubSub.local_broadcast(@pubsub, "block:#{block_id}", msg)
#     end
#   end

#   defp run_miner(round_id, block_id, validator, transactions, pg_conn) do
#     nonce_dets = DetsPlux.get(:nonce)
#     nonce_tx = DetsPlux.tx(nonce_dets, :nonce)
#     dtx = :ets.whereis(:dtx)
#     dtmp = :ets.new(:tmp, [:set])
#     cref = :counters.new(1, [])
#     synced = :persistent_term.get(:status) == :synced

#     Enum.each(transactions, fn
#       ["err", hash, type, from, nonce, args, sig, size] ->
#         Account.gte_nonce(nonce_dets, nonce_tx, from, nonce)

#         if @history do
#           ix = :counters.get(cref, 1)

#           PgStore.insert_tx(pg_conn, [
#             from,
#             nonce,
#             ix,
#             block_id,
#             hash,
#             type,
#             1,
#             size,
#             @cjson,
#             @json.encode!(args),
#             sig
#           ])
#         end

#         if @notify and synced and type != 308 do
#           PubSub.local_broadcast(@pubsub, "pay:#{from}", %{
#             "hash" => Utils.encode16(hash),
#             "nonce" => nonce,
#             "from" => from,
#             "args" => args,
#             "status" => 1,
#             "type" => type
#           })
#         end

#       [hash, type, from, nonce, args, sig, size] ->
#         Account.gte_nonce(nonce_dets, nonce_tx, from, nonce)

#         result = TxHandler.regular()

#         status = tx_status(result)

#         if @notify and synced and type != 308 do
#           PubSub.local_broadcast(@pubsub, "pay:#{from}", %{
#             "hash" => Utils.encode16(hash),
#             "nonce" => nonce,
#             "from" => from,
#             "args" => args,
#             "status" => status,
#             "type" => type
#           })
#         end

#         if @history do
#           ix = :counters.get(cref, 1)

#           PgStore.insert_tx(pg_conn, [
#             from,
#             nonce,
#             ix,
#             block_id,
#             hash,
#             type,
#             tx_status(result),
#             size,
#             @cjson,
#             @json.encode!(args),
#             sig
#           ])

#           # |> IO.inspect()
#         end

#         :counters.add(cref, 1, 1)

#       [hash, type, _arg_key, from, nonce, args, sig, size] ->
#         ix = :counters.get(cref, 1)

#         result =
#           case Account.update_nonce(nonce_dets, nonce_tx, from, nonce) do
#             :error ->
#               :error

#             _true ->
#               TxHandler.insert_deferred(dtx, dtmp)
#           end

#         status = tx_status(result)

#         if @notify and synced and type != 308 do
#           PubSub.local_broadcast(@pubsub, "pay:#{from}", %{
#             "hash" => Utils.encode16(hash),
#             "nonce" => nonce,
#             "from" => from,
#             "args" => args,
#             "status" => status,
#             "type" => type
#           })
#         end

#         if @history do
#           PgStore.insert_tx(pg_conn, [
#             from,
#             nonce,
#             ix,
#             block_id,
#             hash,
#             type,
#             status,
#             size,
#             @cjson,
#             @json.encode!(args),
#             sig
#           ])

#           # |> IO.inspect()
#         end

#         :counters.add(cref, 1, 1)
#     end)
#   end

#   defp tx_status(:error), do: 1
#   defp tx_status(false), do: 1
#   defp tx_status(_), do: 0
# end
