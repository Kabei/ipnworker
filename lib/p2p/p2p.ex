defmodule Ippan.P2P do
  require Logger

  @compile :inline_list_funcs
  @compile {:inline, [decode!: 2, encode: 2]}

  @version <<0::16>>
  @seconds <<0>>
  @iv_bytes 12
  @tag_bytes 16
  @adapter :gen_tcp
  @handshake_timeout 5_000
  @server_ping_timeout 60_000

  @spec client_handshake(
          socket :: port(),
          from_id :: integer() | binary(),
          kem_pubkey :: binary(),
          privkey :: binary()
        ) ::
          {:ok, sharekey :: binary} | {:error, term()} | :halt
  def client_handshake(socket, from_id, kem_pubkey, privkey) do
    {:ok, ciphertext, sharedkey} = NtruKem.enc(kem_pubkey)
    {:ok, signature} = Cafezinho.Impl.sign(sharedkey, privkey)

    data = %{"id" => from_id, "sig" => signature}
    authtext = encode(data, sharedkey)
    @adapter.controlling_process(socket, self())
    @adapter.send(socket, "HI" <> @version <> ciphertext <> authtext)

    case @adapter.recv(socket, 0, @handshake_timeout) do
      {:ok, "WEL"} ->
        {:ok, sharedkey}

      {:ok, _wrong} ->
        @adapter.close(socket)
        :halt

      error ->
        @adapter.close(socket)
        error
    end
  end

  @spec server_handshake(socket :: term, kem_privkey :: binary, fun :: fun()) ::
          {:ok, term, map, integer()} | :error
  def server_handshake(socket, kem_privkey, fun) do
    case @adapter.recv(socket, 0, @handshake_timeout) do
      {:ok, "HI" <> @version <> <<ciphertext::bytes-size(1278), authtext::binary>>} ->
        case NtruKem.dec(kem_privkey, ciphertext) do
          {:ok, sharedkey} ->
            %{"id" => id, "sig" => signature} = decode!(authtext, sharedkey)

            case fun.(id) do
              data = %{pubkey: clientPubkey} ->
                case Cafezinho.Impl.verify(signature, sharedkey, clientPubkey) do
                  :ok ->
                    Logger.debug("[Server connection] #{id} connected")
                    @adapter.send(socket, "WEL")

                    node =
                      data
                      |> Map.take([:id, :hostname, :port, :role, :net_pubkey])
                      |> Map.put(:socket, socket)
                      |> Map.put(:sharedkey, sharedkey)

                    {:ok, id, node, @server_ping_timeout}

                  _ ->
                    Logger.debug("Invalid signature authentication")
                    :error
                end

              _ ->
                Logger.debug("Node not exists: #{id}")
                :error
            end

          _error ->
            Logger.debug("Invalid ntrukem ciphertext authentication")
            :error
        end

      error ->
        Logger.debug("Invalid handshake")
        IO.inspect(error)
        :error
    end
  end

  @spec decode!(data :: binary, sharedkey :: binary) :: term()
  def decode!(
        <<iv::bytes-size(@iv_bytes), tag::bytes-size(@tag_bytes), ciphertext::binary>>,
        sharedkey
      ) do
    x =
      :crypto.crypto_one_time_aead(
        :chacha20_poly1305,
        sharedkey,
        iv,
        ciphertext,
        @seconds,
        tag,
        false
      )
      |> CBOR.Decoder.decode()

    :erlang.element(1, x)
  end

  def decode!(packet, _sharedkey), do: packet

  @spec encode(msg :: term, sharedkey :: binary) :: binary()
  def encode(msg, sharedkey) do
    bin = CBOR.Encoder.encode_into(msg, <<>>)
    iv = :crypto.strong_rand_bytes(@iv_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :chacha20_poly1305,
        sharedkey,
        iv,
        bin,
        @seconds,
        @tag_bytes,
        true
      )

    iv <> tag <> ciphertext
  end
end
