defmodule Ippan.TxHandler do
  alias Ippan.Wallet
  alias Ippan.Funcs
  alias Sqlite3NIF
  require SqliteStore

  @json Application.compile_env(:ipnworker, :json)

  @spec valid!(binary, binary, binary, integer, integer) :: list()
  def valid!(hash, msg, signature, size, validator_node_id) do
    [type, timestamp, from | args] = @json.decode!(msg)

    if timestamp < :persistent_term.get(:time_expired, 0) do
      raise(IppanError, "Invalid timestamp")
    end

    %{deferred: deferred, mod: mod, fun: fun, validator: check_validator} = Funcs.lookup(type)

    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)

    %{pubkey: wallet_pubkey} =
      case check_validator do
        # check from variable
        1 ->
          result =
            %{validator: wallet_validator} =
            SqliteStore.lookup_map(:wallet, conn, stmts, "get_wallet", from, Wallet)

          if wallet_validator != validator_node_id do
            raise IppanRedirectError, "#{validator_node_id}"
          end

          result

        # check first argument
        0 ->
          %{pubkey: args |> hd |> Fast64.decode64()}

        # check first argument
        2 ->
          key = hd(args)

          result =
            %{validator: wallet_validator} =
            SqliteStore.lookup_map(:wallet, conn, stmts, "get_wallet", key, Wallet)

          if wallet_validator != validator_node_id do
            raise IppanRedirectError, "#{wallet_validator}"
          end

          result
      end

    sig_flag = :binary.first(from)
    check_signature!(sig_flag, signature, hash, wallet_pubkey)

    source = %{
      conn: conn,
      dets: :persistent_term.get(:dets_balance),
      hash: hash,
      size: size,
      stmts: stmts,
      timestamp: timestamp,
      validator: :persistent_term.get(:validator)
    }

    :ok = apply(mod, fun, [source | args])

    case deferred do
      false ->
        [
          deferred,
          [
            hash,
            type,
            from,
            args,
            timestamp,
            size
          ],
          [msg, signature]
        ]

      _true ->
        key = hd(args) |> to_string()

        [
          deferred,
          [
            hash,
            type,
            key,
            from,
            args,
            timestamp,
            size
          ],
          [msg, signature]
        ]
    end
  end



  # check signature by type
  # verify ed25519 signature
  defp check_signature!(48, signature, hash, wallet_pubkey) do
    if Cafezinho.Impl.verify(
         signature,
         hash,
         wallet_pubkey
       ) != :ok,
       do: raise(IppanError, "Invalid signature verify")
  end

  # verify falcon-512 signature
  defp check_signature!(49, signature, hash, wallet_pubkey) do
    if Falcon.verify(hash, signature, wallet_pubkey) != :ok,
      do: raise(IppanError, "Invalid signature verify")
  end

  # verify secp256k1 signature
  # defp check_signature!("2", signature, hash, wallet_pubkey) do
  #   if @libsecp256k1.verify(hash, signature, wallet_pubkey) !=
  #        :ok,
  #      do: raise(IppanError, "Invalid signature verify")
  # end

  defp check_signature!(_, _signature, _hash, _wallet_pubkey) do
    raise(IppanError, "Signature type not supported")
  end
end
