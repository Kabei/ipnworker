defmodule Ippan.Func.Service do
  require BalanceStore
  alias Ippan.Utils
  require Sqlite

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)

  def new(%{id: account_id}, id, name, extras) do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Match.account?(id) ->
        raise IppanError, "Invalid ID"

      byte_size(name) > 50 ->
        raise IppanError, "Invalid name length"

      map_size(extras) > 5 ->
        raise IppanError, "Invalid extras key size"

      PayService.exists?(db_ref, id) ->
        raise IppanError, "Already exists service: #{id}"

      true ->
        price = EnvStore.service_price()

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
    end
  end

  def update(%{id: account_id, size: size, validator: %{fa: fa, fb: fb}}, id, map) do
    extra = Map.get(map, "extra")
    MapUtil.validate_length(map, :name, 50)

    cond do
      id != account_id ->
        raise IppanError, "Unauthorized"

      map_size(extra) > 2 ->
        raise IppanError, "Invalid second parameter"

      not is_nil(extra) and map_size(extra) > 5 ->
        raise IppanError, "Invalid extra key size"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def delete(%{id: account_id}, id) do
    if account_id != id or account_id != EnvStore.owner() do
      raise IppanError, "Unauthorized"
    end
  end

  def subscribe(
        %{id: account_id, size: size, validator: %{fa: fa, fb: fb}},
        service_id,
        token_id,
        extras
      ) do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      map_size(extras) > 3 ->
        raise IppanError, "Error extra data format"

      SubPay.has?(db_ref, service_id, token_id, account_id) ->
        raise IppanError, "Already subscribed"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def unsubscribe(%{id: account_id}, service_id, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    unless SubPay.has?(db_ref, service_id, token_id, account_id),
      do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end
end
