defmodule Ippan.Func.Account do
  alias Ippan.Utils
  alias Ippan.{Address, Validator}
  require Validator
  require Sqlite

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)

  def new(
        %{id: account_id, map: account_map, validator: %{id: vid, fa: vfa, fb: vfb}},
        pubkey,
        sig_type,
        validator_id,
        fa,
        fb
      ) do
    pubkey = Fast64.decode64(pubkey)

    cond do
      account_map != nil ->
        raise IppanError, "Account #{account_id} already exists"

      not Match.account?(account_id) ->
        raise IppanError, "Invalid account ID format"

      Match.wallet_address?(account_id) and Address.hash(sig_type, pubkey) != account_id ->
        raise IppanError, "Invalid account ID"

      validator_id != vid ->
        raise IppanError, "Invalid validator"

      vfa != fa or vfb != fb ->
        raise IppanError, "Invalid fees"

      sig_type not in 0..2 ->
        raise IppanError, "Invalid signature type"

      invalid_pubkey_size?(pubkey, sig_type) ->
        raise IppanError, "Invalid pubkey size"

      not is_integer(fa) or fa < EnvStore.min_fa() ->
        raise IppanError, "Invalid FA value"

      not is_integer(fb) or fb < EnvStore.min_fb() ->
        raise IppanError, "Invalid FB value"

      true ->
        :ok
    end
  end

  def subscribe(
        %{
          id: account_id,
          dets: dets,
          map: account_map,
          validator: %{fa: vfa, fb: vfb},
          size: size
        },
        validator_id,
        fa,
        fb
      ) do
    %{"vid" => vid, "fa" => ofa, "fb" => ofb} = account_map

    cond do
      not Match.validator?(validator_id) ->
        raise IppanError, "Invalid validator ID"

      validator_id == vid and ofa == fa and ofb == fb ->
        raise IppanError, "Already subscribed"

      vfa != fa or vfb != fb ->
        raise IppanError, "Invalid fees"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def edit_key(
        %{id: account_id, dets: dets, validator: %{fa: fa, fb: fb}, size: size},
        pubkey,
        sig_type
      ) do
    pubkey = Fast64.decode64(pubkey)

    cond do
      not Match.username?(account_id) ->
        raise IppanError, "Only account with username can edit pubkey"

      invalid_pubkey_size?(pubkey, sig_type) ->
        raise IppanError, "Invalid pubkey size"

      sig_type not in 0..2 ->
        raise IppanError, "Invalid signature type"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  defp invalid_pubkey_size?(pubkey, sig_type) do
    (sig_type == 0 and byte_size(pubkey) != 32) or
      (sig_type == 1 and byte_size(pubkey) == 65) or
      (sig_type == 2 and byte_size(pubkey) != 897)
  end
end
