defmodule Ippan.BlockHandler do
  alias Ippan.{Block, ClusterNodes, Round, Validator, TxHandler}
  # alias Phoenix.PubSub

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1]

  require TxHandler
  require Round
  require Sqlite
  require Validator
  require Logger

  @app Mix.Project.config()[:app]
  @json Application.compile_env(@app, :json)
  # @version Application.compile_env(@app, :version)
  # @max_block_size Application.compile_env(@app, :block_max_size)
  # @pubsub :pubsub

  # @spec check(map) :: :ok | {:error, binary} | :error
  # def check(%{
  #       "creator" => creator_id,
  #       "hash" => hash,
  #       "filehash" => filehash,
  #       "height" => height,
  #       "hostname" => hostname,
  #       "prev" => prev,
  #       "signature" => signature,
  #       "size" => size,
  #       "timestamp" => timestamp,
  #       "vsn" => version
  #     }) do
  #   try do
  #     db_ref = :persistent_term.get(:main_conn)
  #     remote_url = Block.url(hostname, creator_id, height)
  #     output_path = Block.block_path(creator_id, height)
  #     file_exists = File.exists?(output_path)

  #     if file_exists do
  #       {:ok, filestat} = File.stat(output_path)

  #       if filestat.size != size do
  #         File.rm(output_path)
  #         DownloadTask.start(remote_url, output_path, @max_block_size)
  #       end
  #     else
  #       DownloadTask.start(remote_url, output_path, @max_block_size)
  #     end
  #     |> case do
  #       :ok ->
  #         :ok

  #       _error ->
  #         raise IppanError, "Error downloading blockfile"
  #     end

  #     IO.inspect("stats")
  #     {:ok, filestat} = File.stat(output_path)
  #     %{pubkey: pubkey} = Validator.get(creator_id)

  #     cond do
  #       filestat.size > @max_block_size or filestat.size != size ->
  #         raise IppanError, "Invalid block size"

  #       hash != Block.compute_hash(creator_id, height, prev, filehash, timestamp) ->
  #         raise(IppanError, "Invalid block hash")

  #       filehash != hash_file(output_path) ->
  #         raise(IppanError, "Hash block file is invalid")

  #       Cafezinho.Impl.verify(signature, hash, pubkey) != :ok ->
  #         raise(IppanError, "Invalid block signature")

  #       @version != version ->
  #         raise(IppanError, "Invalid block version")

  #       true ->
  #         :ok
  #     end
  #   rescue
  #     e in IppanError ->
  #       {:error, e.message}

  #     err ->
  #       Logger.error(Exception.format(:error, err, __STACKTRACE__))
  #       :error
  #   end
  # end

  # def check(_), do: {:error, "Bad map format"}

  @spec verify_block(map) :: :ok | :error | {:error, any}
  def verify_block(%{
        # "round" => block_round_id,
        "count" => count,
        "creator" => creator_id,
        "height" => height,
        "vsn" => version
      }) do
    output_path = Block.block_path(creator_id, height)
    miner = :persistent_term.get(:miner)
    node = ClusterNodes.info(miner)
    url = Block.cluster_block_url(node.hostname, creator_id, height)

    case DownloadTask.start(url, output_path) do
      :ok ->
        db_ref = :persistent_term.get(:main_conn)
        wallet_dets = DetsPlux.get(:wallet)
        wallet_tx = DetsPlux.tx(:wallet)
        nonce_dets = DetsPlux.get(:nonce)
        nonce_tx = DetsPlux.tx(nonce_dets, :cache_nonce)
        validator = Validator.get(creator_id)

        IO.inspect(output_path)
        IO.inspect("File.read")
        {:ok, content} = File.read(output_path)
        %{"vsn" => vsn, "data" => messages} = decode_file!(content)

        IO.inspect("Version")

        if vsn == version do
          ets = :ets.new(:temp, [:set])

          IO.inspect("before check hash duplic")

          try do
            values =
              Enum.reduce(messages, [], fn [body, signature], acc ->
                hash = Blake3.hash(body)
                size = byte_size(body) + byte_size(signature)
                [type, nonce, from | args] = @json.decode!(body)

                try do
                  result = TxHandler.decode_from_file!()

                  case :ets.insert_new(ets, {{from, nonce}, nil}) do
                    true ->
                      [result | acc]

                    false ->
                      :ets.delete(ets)
                      raise IppanHighError, "Invalid block transaction duplicated"
                  end
                rescue
                  IppanHighError ->
                    reraise IppanHighError, __STACKTRACE__

                  [IppanError, IppanRedirectError] ->
                    [["err", hash, type, from, nonce, args, signature, size] | acc]

                  err ->
                    Logger.error(Exception.format(:error, err, __STACKTRACE__))
                end
              end)
              |> Enum.reverse()

            :ets.delete(ets)

            IO.inspect("after check hash duplic")

            if count != Enum.count(values) do
              raise IppanError, "Invalid block messages count"
            end

            IO.puts("before export")

            export_path = Block.decode_path(creator_id, height)

            IO.inspect(export_path)

            File.write(
              export_path,
              encode_file!(%{"data" => values, "vsn" => version})
            )
        rescue
          _ ->
            :error
          end
        else
          {:error, "Bad version"}
        end
        _error ->
          IO.puts("error download file")
          :error
        end
      end

  def verify_block(_), do: :error

  # defp check_round!(block_round_id, current_round_id) do
  #   if current_round_id + 1 != block_round_id do
  #     PubSub.subscribe(@pubsub, "round.new")

  #     loop_wait!(block_round_id, current_round_id)
  #   end
  # end

  # defp loop_wait!(block_round_id, current_round_id) do
  #   receive do
  #     %{"id" => rid} when rid + 1 == block_round_id ->
  #       PubSub.unsubscribe(@pubsub, "round.new")

  #     _ ->
  #       loop_wait!(block_round_id, current_round_id)
  #   after
  #     10_000 ->
  #       PubSub.unsubscribe(@pubsub, "round.new")
  #       raise RuntimeError, "Timeout Rounds not equals"
  #   end
  # end
end
