defmodule Ippan.BlockHandler do
  alias Ippan.{Block, TxHandler}

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1, hash_file: 1]

  @version Application.compile_env(:ipnworker, :version)
  @max_block_size Application.compile_env(:ipnworker, :block_max_size)

  @spec verify_file!(map) :: :ok | :error
  def verify_file!(%{
        "height" => height,
        "hash" => hash,
        "hashfile" => hashfile,
        "creator" => creator_id,
        "prev" => prev,
        "signature" => signature,
        "timestamp" => timestamp,
        "count" => count,
        "size" => size,
        "vsn" => version,
        "hostname" => hostname,
        "pubkey" => pubkey
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

          decode_msgs =
            Enum.reduce(messages, %{}, fn [msg, sig], acc ->
              hash = Blake3.hash(msg)
              size = byte_size(msg) + byte_size(sig)

              [_deferred, msg] =
                TxHandler.valid!(hash, msg, sig, size, creator_id)

              Map.put(acc, hash, msg)
            end)
            |> Map.values()

          if count != length(decode_msgs) do
            raise IppanError, "Invalid block messages count"
          end

          export_path = Path.join(:persistent_term.get(:decode_dir), filename)

          :ok = File.write(export_path, encode_file!(decode_msgs))
      end
    rescue
      _error ->
        :error
    end
  end
end
