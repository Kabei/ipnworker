defmodule Ippan.TxHandler do
  alias Ippan.{Funcs, Wallet}
  alias Ippan.TxHandler

  defmacro get_public_key!(dets, tx, type, vid) do
    quote location: :keep, bind_quoted: [dets: dets, tx: tx, type: type, vid: vid] do
      case type do
        # check from variable
        0 ->
          {pk, v} =
            DetsPlux.get_cache(dets, tx, var!(from))

          if vid != v do
            raise IppanRedirectError, "#{v}"
          end

          pk

        # get first argument and not check (wallet subscribe)
        1 ->
          Fast64.decode64(hd(var!(args)))

        # check first argument
        2 ->
          key = hd(var!(args))

          {pk, v} =
            DetsPlux.get_tx(dets, tx, key)

          if v != vid do
            raise IppanRedirectError, "#{v}"
          end

          pk
      end
    end
  end

  # check signature by type
  defmacro check_signature!(sig_type, pk) do
    quote location: :keep,
          bind_quoted: [pk: pk, sig_type: sig_type] do
      case sig_type do
        "0" ->
          # verify ed25519 signature
          if Cafezinho.Impl.verify(var!(signature), var!(hash), pk) != :ok,
            do: raise(IppanError, "Invalid signature verify")

        "1" ->
          # verify falcon-512 signature
          if Falcon.verify(var!(hash), var!(signature), pk) != :ok,
            do: raise(IppanError, "Invalid signature verify")

        _ ->
          raise(IppanError, "Signature type not supported")
      end
    end
  end

  # @spec valid!(reference, map, binary, binary, binary, integer, integer, map) :: list()
  # (conn, stmts, hash, msg, signature, size, validator_id, validator)
  defmacro decode! do
    quote location: :keep do
      %{deferred: deferred, mod: mod, fun: fun, check: type_of_verification} =
        Funcs.lookup(var!(type))

      wallet_dets = DetsPlux.get(:wallet)
      wallet_cache = DetsPlux.tx(wallet_dets, :cache_wallet)

      wallet_pk =
        TxHandler.get_public_key!(wallet_dets, wallet_cache, type_of_verification, var!(vid))

      [sig_type, _] = String.split(var!(from), "x", parts: 2)
      TxHandler.check_signature!(sig_type, wallet_pk)

      # Check nonce
      nonce_dets = DetsPlux.get(:nonce)
      cache_nonce_tx = DetsPlux.tx(nonce_dets, :cache_nonce)
      nonce_key = Wallet.gte_nonce!(nonce_dets, cache_nonce_tx, var!(from), var!(nonce))
      balance_dets = DetsPlux.get(:balance)

      source = %{
        id: var!(from),
        hash: var!(hash),
        size: var!(size),
        type: var!(type),
        validator: var!(validator)
      }

      return = apply(mod, fun, [source | var!(args)])

      # Update nonce
      DetsPlux.put(cache_nonce_tx, nonce_key, var!(nonce))

      case deferred do
        false ->
          [
            deferred,
            [
              var!(hash),
              var!(type),
              var!(from),
              var!(nonce),
              var!(args),
              [var!(body), var!(signature)],
              var!(size)
            ],
            return
          ]

        _true ->
          key = hd(var!(args)) |> to_string()

          [
            deferred,
            [
              var!(hash),
              var!(type),
              key,
              var!(from),
              var!(nonce),
              var!(args),
              [var!(body), var!(signature)],
              var!(size)
            ],
            return
          ]
      end
    end
  end

  defmacro decode_from_file! do
    quote location: :keep do
      %{deferred: deferred, mod: mod, fun: fun, check: type_of_verification} =
        Funcs.lookup(var!(type))

      wallet_pk =
        TxHandler.get_public_key!(
          var!(wallet_dets),
          var!(wallet_tx),
          type_of_verification,
          var!(creator_id)
        )

      [sig_type, _] = String.split(var!(from), "x", parts: 2)
      TxHandler.check_signature!(sig_type, wallet_pk)

      Wallet.update_nonce!(var!(wallet_dets), var!(nonce_tx), var!(from), var!(nonce))

      source = %{
        id: var!(from),
        hash: var!(hash),
        size: var!(size),
        type: var!(type),
        validator: var!(validator)
      }

      apply(mod, fun, [source | var!(args)])

      case deferred do
        false ->
          [
            var!(hash),
            var!(type),
            var!(from),
            var!(nonce),
            var!(args),
            var!(size)
          ]

        _true ->
          key = hd(var!(args)) |> to_string()

          [
            var!(hash),
            var!(type),
            key,
            var!(from),
            var!(nonce),
            var!(args),
            var!(size)
          ]
      end
    end
  end

  @spec regular() :: any | :error
  defmacro regular do
    quote location: :keep do
      %{fun: fun, modx: module} = Funcs.lookup(var!(type))

      source = %{
        block: var!(block_id),
        hash: var!(hash),
        id: var!(from),
        round: var!(round_id),
        size: var!(size),
        type: var!(type),
        validator: var!(validator)
      }

      apply(module, fun, [source | var!(args)])
    end
  end

  # Dispute resolution in deferred transaction
  # [hash, type, arg_key, account_id, args, _nonce, size],
  # validator_id,
  # block_id
  @spec insert_deferred() :: boolean()
  defmacro insert_deferred do
    quote location: :keep do
      key = {var!(type), var!(arg_key)}
      # body = [hash, account_id, validator_id, args, size, block_id]

      case :ets.lookup(:dtx, key) do
        [] ->
          :ets.insert(:dtx, {key, var!(body)})

        [{_msg_key, [xhash | _rest] = xbody}] ->
          xblock_id = List.last(xbody)

          if var!(hash) < xhash or (var!(hash) == xhash and var!(block_id) < xblock_id) do
            :ets.insert(:dtx, {key, var!(body)})
          else
            false
          end
      end
    end
  end

  # only deferred transactions
  # def run_deferred_txs(conn, stmts, balance_pid, balance_tx, wallets) do
  defmacro run_deferred_txs do
    quote location: :keep do
      :ets.tab2list(:dtx)
      |> Enum.each(fn {{type, _key},
                       [
                         hash,
                         account_id,
                         validator_id,
                         args,
                         size,
                         block_id
                       ]} ->
        %{modx: module, fun: fun} = Funcs.lookup(type)

        source = %{
          block: block_id,
          hash: hash,
          id: account_id,
          round: var!(round_id),
          size: size,
          type: type,
          validator: validator_id
        }

        apply(module, fun, [source | args])
      end)

      :ets.delete_all_objects(:dtx)
    end
  end
end
