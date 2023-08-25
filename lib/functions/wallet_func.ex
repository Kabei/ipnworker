defmodule Ippan.Func.Wallet do
  alias Ippan.Address
  require SqliteStore

  def subscribe(
        %{conn: conn, stmts: stmts},
        pubkey,
        validator_id,
        sig_type
      )
      when is_integer(validator_id) do
    pubkey = Fast64.decode64(pubkey)
    id = Address.hash(sig_type, pubkey)

    cond do
      sig_type not in 0..2 ->
        raise IppanError, "Invalid signature type"

      byte_size(pubkey) > 897 ->
        raise IppanError, "Invalid pubkey size"

      SqliteStore.exists?(conn, stmts, "exists_wallet", [id, sig_type]) ->
        raise IppanError, "Already exists"

      true ->
        :ok
    end
  end

  def unsubscribe(
        %{
          validator: validator,
          conn: conn,
          stmts: stmts
        },
        new_validator_id
      ) do
    cond do
      validator.id == new_validator_id ->
        raise IppanError, "Already subscribe"

      not SqliteStore.exists?(conn, stmts, "exists_validator", new_validator_id) ->
        raise IppanError, "Validator not exists"

      true ->
        :ok
    end
  end
end
