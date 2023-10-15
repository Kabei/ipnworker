defmodule Ippan.BlockHandler do
  alias Ippan.Validator
  alias Ippan.{Block, TxHandler}

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1, hash_file: 1]

  require TxHandler
  require SqliteStore

  @version Application.compile_env(:ipnworker, :version)
  @max_block_size Application.compile_env(:ipnworker, :block_max_size)
  @json Application.compile_env(:ipnworker, :json)

  @spec verify_file!(map) :: :ok | :error
  def verify_file!(%{
        "count" => count,
        "creator" => creator_id,
        "hash" => hash,
        "hashfile" => hashfile,
        "height" => height,
        "hostname" => hostname,
        "prev" => prev,
        "pubkey" => pubkey,
        "signature" => signature,
        "size" => size,
        "timestamp" => timestamp,
        "vsn" => version
      }) do
    try do
      remote_url = Block.url(hostname, creator_id, height)
      output_path = Block.block_path(creator_id, height)
      file_exists = File.exists?(output_path)
      filename = Path.basename(output_path)

      unless file_exists do
        :ok = Download.from(remote_url, output_path, @max_block_size)
      else
        {:ok, filestat} = File.stat(output_path)

        if filestat.size != size do
          :ok = Download.from(remote_url, output_path, @max_block_size)
        end
      end

      {:ok, filestat} = File.stat(output_path)

      cond do
        filestat.size > @max_block_size or filestat.size != size ->
          raise IppanError, "Invalid block size"

        hash != Block.compute_hash(creator_id, height, prev, hashfile, timestamp) ->
          raise(IppanError, "Invalid block hash")

        hashfile != hash_file(output_path) ->
          raise(IppanError, "Hash block file is invalid")

        Cafezinho.Impl.verify(signature, hash, pubkey) != :ok ->
          raise(IppanError, "Invalid block signature")

        @version != version ->
          raise(IppanError, "Invalid block version")

        true ->
          {:ok, content} = File.read(output_path)
          %{"vsn" => vsn, "data" => messages} = decode_file!(content)

          if vsn != version do
            raise(IppanError, "Invalid blockfile version")
          end

          conn = :persistent_term.get(:asset_conn)
          stmts = :persistent_term.get(:asset_stmt)
          wallet_dets = DetsPlux.get(:wallet)
          wallet_tx = DetsPlux.tx(:wallet)
          nonce_tx = DetsPlux.tx(wallet_dets, :cache_nonce)

          validator =
            SqliteStore.lookup_map(
              :validator,
              conn,
              stmts,
              "get_validator",
              creator_id,
              Validator
            )

          umap =
            Enum.reduce(messages, UMap.new(), fn [body, signature], acc ->
              hash = Blake3.hash(body)
              size = byte_size(body) + byte_size(signature)
              [type, timestamp, nonce, from | args] = @json.decode!(body)

              try do
                result =
                  TxHandler.decode_from_file!()

                UMap.put_new(acc, hash, result)
              catch
                _ -> acc
              end
            end)

          if count != UMap.size(umap) do
            raise IppanError, "Invalid block messages count"
          end

          export_path = Path.join(:persistent_term.get(:decode_dir), filename)

          :ok =
            File.write(
              export_path,
              encode_file!(%{"data" => UMap.values(umap), "vsn" => version})
            )
      end
    rescue
      error ->
        IO.inspect(error)
        :error
    end
  end

  def verify_file!(_), do: :error
end
