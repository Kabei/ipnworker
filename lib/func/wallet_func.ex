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
        sig_type,
        validator_id,
        fa,
        fb
      ) do
    pubkey = Fast64.decode64(pubkey)
    id = Address.hash(sig_type, pubkey)
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(dets, :cache_wallet)

    cond do
      id != account_id ->
        raise IppanError, "Invalid account ID"

      validator_id != validator.id ->
        raise IppanError, "Invalid validator"

      sig_type not in 0..2 ->
        raise IppanError, "Invalid signature type"

      (sig_type == 0 and byte_size(pubkey) != 32) or
        (sig_type == 1 and byte_size(pubkey) == 65) or
          (sig_type == 2 and byte_size(pubkey) != 897) ->
        raise IppanError, "Invalid pubkey size"

      not is_integer(fa) or fa < EnvStore.min_fa() ->
        raise IppanError, "Invalid FA"

      not is_integer(fb) or fb < EnvStore.min_fb() ->
        raise IppanError, "Invalid FB"

      DetsPlux.member_tx?(dets, tx, id) ->
        raise IppanError, "Wallet #{id} already exists"

      true ->
        :ok
    end
  end

  def subscribe(
        %{id: account_id, validator: %{fa: vfa, fb: vfb}, size: size},
        validator_id,
        fa,
        fb
      )
      when vfa == fa and vfb == fb do
    wallet_dets = DetsPlux.get(:wallet)
    wallet_cache = DetsPlux.tx(wallet_dets, :cache_wallet)

    {_pk, vid, _sig_type} =
      DetsPlux.get_cache(wallet_dets, wallet_cache, account_id)

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
