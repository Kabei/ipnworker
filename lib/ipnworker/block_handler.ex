defmodule Ippan.BlockHandler do
  alias Ippan.{Block, TxHandler}

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1, hash_file: 1]

  @version Application.compile_env(:ipnworker, :version)
  @block_extension Application.compile_env(:ipnworker, :block_extension)
  @max_block_data_size Application.compile_env(:ipnworker, :max_block_data_size)
  @max_block_size Application.compile_env(:ipnworker, :block_max_size)

  # Generate local block and decode block file
  @spec generate_files(creator_id :: integer(), height :: integer()) :: map | nil
  def generate_files(creator_id, height) do
    filename = "#{creator_id}.#{height}.#{@block_extension}"
    block_path = Path.join(Application.get_env(:ipnworker, :block_dir), filename)
    decode_path = Path.join(Application.get_env(:ipnworker, :decode_dir), filename)
    ets_msg = :ets.whereis(:msg)

    if :ets.info(ets_msg, :size) > 0 do
      {acc_msg, acc_decode} =
        do_iterate(ets_msg, :ets.first(ets_msg), %{}, %{}, 0)

      content = encode_file!(%{"msg" => acc_msg, "vsn" => @version})

      File.write(block_path, content)
      File.write(decode_path, encode_file!(%{"msg" => acc_decode, "vsn" => @version}))

      {:ok, file_info} = File.stat(block_path)

      %{
        count: length(acc_msg),
        creator: creator_id,
        hash: hash_file(block_path),
        height: height,
        size: file_info.size
      }
    end
  end

  defp do_iterate(_ets_msg, :"$end_of_table", messages, decode_messages, _),
    do: {Map.values(messages), Map.values(decode_messages)}

  defp do_iterate(ets_msg, key, messages, decode_message, acc_size) do
    [msg] = :ets.lookup(ets_msg, key)

    {acc_msg, acc_decode, size} =
      case msg do
        {
          hash,
          timestamp,
          type,
          from,
          args,
          msg_sig,
          size
        } ->
          acc_msg = Map.put(messages, hash, msg_sig)

          acc_decode =
            Map.put(hash, decode_message, [
              hash,
              timestamp,
              type,
              from,
              args,
              size
            ])

          {acc_msg, acc_decode, size}

        {
          hash,
          timestamp,
          _key,
          type,
          from,
          args,
          msg_sig,
          size
        } ->
          acc_msg = Map.put(hash, messages, msg_sig)

          acc_decode =
            Map.put(hash, decode_message, [
              hash,
              timestamp,
              type,
              from,
              args,
              size
            ])

          {acc_msg, acc_decode, size}
      end

    acc_size = acc_size + size

    case @max_block_data_size > acc_size do
      false ->
        :ets.delete(ets_msg, key)
        do_iterate(ets_msg, :ets.next(ets_msg, key), acc_msg, acc_decode, acc_size)

      _true ->
        {Map.values(acc_msg), Map.values(acc_decode)}
    end
  end

  @spec verify_file!(map) :: :ok | {:error, term()}
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

        true ->
          :ok
      end

      {:ok, content} = File.read(output_path)
      %{"vsn" => vsn, "data" => messages} = decode_file!(content)

      if vsn != version do
        raise(IppanError, "Invalid block version")
      end

      decode_msgs =
        Enum.reduce(messages, %{}, fn [msg, sig], acc ->
          hash = Blake3.hash(msg)
          size = byte_size(msg) + byte_size(sig)

          {msg, _deferred} =
            TxHandler.valid!(hash, msg, sig, size, creator_id)

          Map.put(acc, hash, msg)
        end)
        |> Map.values()

      if count != length(decode_msgs) do
        raise IppanError, "Invalid block messages count"
      end

      export_path = Path.join(:persistent_term.get(:decode_dir), filename)

      :ok = File.write(export_path, encode_file!(decode_msgs))
    rescue
      e ->
        {:error, e.message}
    end
  end
end
