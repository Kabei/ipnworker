defmodule Ippan.BlockHandler do
  alias Ippan.Validator
  alias Ippan.{Block, TxHandler}

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1, hash_file: 1]

  require TxHandler
  require Sqlite
  require Validator
  require Logger

  @app Mix.Project.config()[:app]
  @version Application.compile_env(@app, :version)
  @max_block_size Application.compile_env(@app, :block_max_size)
  @json Application.compile_env(@app, :json)

  @spec verify_file!(map) :: :ok | :error
  def verify_file!(%{
        "count" => count,
        "creator" => creator_id,
        "hash" => hash,
        "filehash" => filehash,
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

      IO.inspect(remote_url)
      IO.inspect(output_path)
      IO.inspect(file_exists)

      unless file_exists do
        :ok = Download.await(remote_url, output_path, @max_block_size)
      else
        {:ok, filestat} = File.stat(output_path)

        if filestat.size != size do
          :ok = Download.await(remote_url, output_path, @max_block_size)
        end
      end

      IO.inspect("stats")
      {:ok, filestat} = File.stat(output_path)

      cond do
        filestat.size > @max_block_size or filestat.size != size ->
          raise IppanError, "Invalid block size"

        hash != Block.compute_hash(creator_id, height, prev, filehash, timestamp) ->
          raise(IppanError, "Invalid block hash")

        filehash != hash_file(output_path) ->
          raise(IppanError, "Hash block file is invalid")

        Cafezinho.Impl.verify(signature, hash, pubkey) != :ok ->
          raise(IppanError, "Invalid block signature")

        @version != version ->
          raise(IppanError, "Invalid block version")

        true ->
          IO.inspect("File.read")
          {:ok, content} = File.read(output_path)
          %{"vsn" => vsn, "data" => messages} = decode_file!(content)

          IO.inspect("Version")

          if vsn != version do
            raise(IppanError, "Invalid blockfile version")
          end

          db_ref = :persistent_term.get(:main_conn)
          wallet_dets = DetsPlux.get(:wallet)
          wallet_tx = DetsPlux.tx(:wallet)
          nonce_dets = DetsPlux.get(:nonce)
          nonce_tx = DetsPlux.tx(nonce_dets, :cache_nonce)
          validator = Validator.get(creator_id)

          ets = :ets.new(:temp, [:set])

          IO.inspect("before check hash duplic")

          values =
            Enum.reduce(messages, [], fn [body, signature], acc ->
              hash = Blake3.hash(body)
              size = byte_size(body) + byte_size(signature)
              [type, nonce, from | args] = @json.decode!(body)

              result = TxHandler.decode_from_file!()

              case :ets.insert_new(ets, {{from, nonce}, nil}) do
                true ->
                  [result | acc]

                false ->
                  :ets.delete(ets)
                  raise IppanError, "Invalid block transaction duplicated"
              end
            end)
            |> Enum.reverse()

          :ets.delete(ets)

          IO.inspect("after check hash duplic")

          if count != Enum.count(values) do
            raise IppanError, "Invalid block messages count"
          end

          IO.inspect("before export")

          export_path = Block.decode_path(creator_id, height)

          IO.inspect(export_path)

          :ok =
            File.write(
              export_path,
              encode_file!(%{"data" => values, "vsn" => version})
            )
      end
    rescue
      err ->
        Logger.error(Exception.format(:error, err, __STACKTRACE__))
        :error
    end
  end

  def verify_file!(_), do: :error
end
