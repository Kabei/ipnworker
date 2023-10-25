defmodule Ippan.Func.Wallet do
  alias Ippan.{Address, Validator}
  require Validator
  require Sqlite

  def new(
        %{id: account_id, validator: validator},
        pubkey,
        validator_id,
        sig_type
      ) do
    pubkey = Fast64.decode64(pubkey)
    id = Address.hash(sig_type, pubkey)
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(:cache_wallet)

    cond do
      id != account_id ->
        raise IppanError, "Invalid sender"

      validator_id != validator.id ->
        raise IppanError, "Invalid validator"

      sig_type not in 0..1 ->
        raise IppanError, "Invalid signature type"

      byte_size(pubkey) > 897 ->
        raise IppanError, "Invalid pubkey size"

      DetsPlux.member_tx?(dets, tx, id) ->
        raise IppanError, "Wallet already exists"

      true ->
        :ok
    end
  end

  def subscribe(%{validator: validator}, validator_id) do
    cond do
      validator_id == validator.id ->
        raise IppanError, "Already subscribe"

      true ->
        :ok
    end
  end
end
