defmodule Ippan.Func.Wallet do
  alias Ippan.Utils
  alias Ippan.{Address, Validator}
  require Validator
  require Sqlite

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)

  def new(
        %{id: account_id, validator: validator},
        pubkey,
        validator_id,
        sig_type
      ) do
    pubkey = Fast64.decode64(pubkey)
    id = Address.hash(sig_type, pubkey)
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(dets, :cache_wallet)

    cond do
      id != account_id ->
        raise IppanError, "Invalid sender"

      validator_id != validator.id ->
        raise IppanError, "Invalid validator"

      sig_type not in 0..2 ->
        raise IppanError, "Invalid signature type"

      (sig_type == 0 and byte_size(pubkey) != 32) or
        (sig_type == 1 and byte_size(pubkey) == 65) or
          (sig_type == 2 and byte_size(pubkey) != 897) ->
        raise IppanError, "Invalid pubkey size"

      DetsPlux.member_tx?(dets, tx, id) ->
        raise IppanError, "Wallet already exists"

      true ->
        :ok
    end
  end

  def subscribe(
        %{id: account_id, validator: %{id: vid, fa: fa, fb: fb}, size: size},
        validator_id
      ) do
    cond do
      validator_id == vid ->
        raise IppanError, "Already subscribe"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end
end
