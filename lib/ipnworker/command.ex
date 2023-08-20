defmodule Ippan.CommandHandler do
  alias Ippan.{Events, Block}
  require Global

  import Ippan.Block,
    only: [decode_file!: 1, encode_file!: 1, hash_file: 1]

  # @libsecp256k1 ExSecp256k1.Impl
  @json Application.compile_env(:ipnworker, :json)
  @max_block_size Application.compile_env(:ipnworker, :block_max_size)
  @block_file_ext Application.compile_env(:ipnworker, :block_file_ext)

  @spec valid!(binary, binary, binary, non_neg_integer(), non_neg_integer()) :: any | no_return()
  def valid!(hash, msg, signature, size, node_validator_id) do
    [type, timestamp, from | args] = @json.decode!(msg)

    if timestamp < Global.expiry_time() do
      raise(IppanError, "Invalid timestamp")
    end

    %{validator: valid_validator, deferred: deferred} = Events.lookup(type)

    {wallet_pubkey, wallet_validator} =
      case valid_validator do
        true ->
          {_id, wallet_pubkey, wallet_validator, _created_at} = WalletStore.lookup(from)
          if wallet_validator != node_validator_id, do: raise(IppanError, "Invalid validator")
          {wallet_pubkey, wallet_validator}

        _false ->
          {_id, wallet_pubkey, wallet_validator, _created_at} = WalletStore.lookup(from)
          {wallet_pubkey, wallet_validator}
      end

    sig_flag = :binary.at(from, 0)
    chech_signature!(sig_flag, signature, hash, wallet_pubkey)

    case deferred do
      false ->
        {
          {
            hash,
            timestamp,
            type,
            from,
            wallet_validator,
            :erlang.term_to_binary(args),
            [msg, signature],
            size
          },
          deferred
        }

      _true ->
        key = hd(args) |> to_string()

        {
          {
            hash,
            timestamp,
            key,
            type,
            from,
            wallet_validator,
            :erlang.term_to_binary(args),
            [msg, signature],
            size
          },
          deferred
        }
    end
  end

  def generate_files(creator_id, block_id) do
    filename = "#{creator_id}.#{block_id}.#{@block_file_ext}"
    block_path = Path.join(Application.get_env(:ipnworker, :block_dir), filename)
    decode_path = Path.join(Application.get_env(:ipnworker, :decode_dir), filename)

    {acc_msg, acc_decode} =
      do_iterate(:ets.first(:msg), %{}, %{}, 0)

    File.write(block_path, encode_file!(acc_msg))

    File.write(decode_path, encode_file!(acc_decode))
  end

  defp do_iterate(:"$end_of_table", messages, decode_messages, _),
    do: {Map.values(messages), Map.values(decode_messages)}

  defp do_iterate(key, messages, decode_message, acc_size) do
    [msg] = :ets.lookup(:msg, key)
    :ets.delete(:msg, key)

    {acc_msg, acc_decode, size} =
      case msg do
        {
          hash,
          timestamp,
          type,
          from,
          wallet_validator,
          args,
          msg_sig,
          size
        } ->
          acc_msg = Map.put(messages, hash, msg_sig)

          acc_decode =
            Map.put(hash, decode_message, [hash, timestamp, type, from, wallet_validator, args])

          {acc_msg, acc_decode, size}

        {
          hash,
          timestamp,
          _key,
          type,
          from,
          wallet_validator,
          args,
          msg_sig,
          size
        } ->
          acc_msg = Map.put(hash, messages, msg_sig)

          acc_decode =
            Map.put(hash, decode_message, [hash, timestamp, type, from, wallet_validator, args])

          {acc_msg, acc_decode, size}
      end

    acc_size = acc_size + size

    case @max_block_size > acc_size do
      false ->
        do_iterate(:ets.next(:msg, key), acc_msg, acc_decode, acc_size)

      _true ->
        {Map.values(acc_msg), Map.values(acc_decode)}
    end
  end

  @spec verify_file!(term, term) :: :ok | no_return()
  def verify_file!(
        %{
          height: height,
          hash: hash,
          hashfile: hashfile,
          creator: creator_id,
          prev: prev,
          signature: signature,
          timestamp: timestamp,
          count: count,
          size: size,
          vsn: version
        },
        %{hostname: hostname, pubkey: pubkey}
      ) do
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

      hash != Block.compute_hash(height, creator_id, prev, hashfile, timestamp) ->
        raise(IppanError, "Invalid block hash")

      hashfile != hash_file(output_path) ->
        raise(IppanError, "Hash block file is invalid")

      Cafezinho.Impl.verify(signature, hash, pubkey) != :ok ->
        raise(IppanError, "Invalid block signature")
    end

    {:ok, content} = File.read(output_path)
    %{vsn: vsn, data: events} = decode_file!(content)

    if vsn != version do
      raise(IppanError, "Invalid block version")
    end

    try do
      decode_events =
        Enum.reduce(events, %{}, fn [msg, sig], acc ->
          hash = Blake3.hash(msg)
          size = byte_size(msg) + byte_size(sig)

          {msg, _deferred} =
            valid!(hash, msg, sig, size, creator_id)

          Map.put(acc, hash, msg)
        end)
        |> Map.values()

      if count != length(decode_events) do
        raise(IppanError, "Invalid block messages count")
      end

      export_path =
        Application.get_env(:ipnworker, :decode_dir)
        |> Path.join(filename)

      :ok = File.write(export_path, encode_file!(decode_events))
    rescue
      e ->
        {:error, e.message}
    end
  end

  # check signature by type
  # verify ed25519 signature
  defp chech_signature!("0", signature, hash, wallet_pubkey) do
    if Cafezinho.Impl.verify(
         signature,
         hash,
         wallet_pubkey
       ) != :ok,
       do: raise(IppanError, "Invalid signature verify")
  end

  # verify falcon-512 signature
  defp chech_signature!("1", signature, hash, wallet_pubkey) do
    if Falcon.verify(hash, signature, wallet_pubkey) != :ok,
      do: raise(IppanError, "Invalid signature verify")
  end

  # verify secp256k1 signature
  # defp chech_signature!("2", signature, hash, wallet_pubkey) do
  #   if @libsecp256k1.verify(hash, signature, wallet_pubkey) !=
  #        :ok,
  #      do: raise(IppanError, "Invalid signature verify")
  # end

  defp chech_signature!(_, _signature, _hash, _wallet_pubkey) do
    raise(IppanError, "Signature type not supported")
  end
end
