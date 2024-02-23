defmodule Ippan.Func.Service do
  require BalanceStore
  alias Ippan.Utils
  require Sqlite

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @name_max_length 50

  def new(%{id: account_id}, id, name, extras) do
    db_ref = :persistent_term.get(:main_conn)
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(dets, :cache_wallet)

    cond do
      not Match.account?(id) ->
        raise IppanError, "Invalid ID"

      not DetsPlux.member_tx?(dets, tx, id) ->
        raise IppanError, "Account \"#{id}\" not exists"

      byte_size(name) > @name_max_length ->
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

  def update(%{id: account_id, size: size, validator: %{fa: fa, fb: fb}}, id, map) when is_map(map) do
    extra = Map.delete(map, "name")
    MapUtil.validate_length(map, :name, @name_max_length)
    db_ref = :persistent_term.get(:main_conn)

    cond do
      id != account_id ->
        raise IppanError, "Unauthorized"

      not PayService.exists?(db_ref, id) ->
        raise IppanError, "Not exists service: #{id}"

      extra != nil and map_size(extra) > 2 ->
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
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not PayService.exists?(db_ref, id) ->
        raise IppanError, "Service #{id} not exists"

      account_id != id and account_id != EnvStore.owner() ->
        raise IppanError, "Unauthorized"

      true -> :ok
    end
  end

  def subscribe(
        %{id: account_id, size: size, validator: %{fa: fa, fb: fb}},
        service_id,
        token_id,
        max_amount
      )
      when is_integer(max_amount) and max_amount > 0 do
    db_ref = :persistent_term.get(:main_conn)

    case PayService.get(db_ref, service_id) do
      nil ->
        raise IppanError, "Service ID not exists"

      %{extra: extra} ->
        min_amount = Map.get(extra, "min_amount", 0)

        cond do
          SubPay.has?(db_ref, service_id, account_id, token_id) ->
            raise IppanError, "Already subscribed"

          min_amount > max_amount ->
            raise IppanError, "Set a max_amount mayor than #{min_amount}"

          true ->
            fees = Utils.calc_fees(fa, fb, size)

            BalanceTrace.new(account_id)
            |> BalanceTrace.requires!(@token, fees)
            |> BalanceTrace.output()
        end
    end
  end

  def unsubscribe(%{id: account_id}, service_id, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    unless SubPay.has?(db_ref, service_id, account_id, token_id),
      do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end
end
