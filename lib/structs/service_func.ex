defmodule Ippan.Func.Service do
  require BalanceStore
  alias Ippan.{Token, Utils}
  require Sqlite
  require Token

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @name_max_length 50
  @max_services Application.compile_env(@app, :max_services, 0)

  def new(%{id: account_id}, id, name, image, extra) do
    db_ref = :persistent_term.get(:main_conn)
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(dets, :cache_wallet)
    stats = Stats.new()

    cond do
      not Match.account?(id) ->
        raise IppanError, "Invalid ID"

      not DetsPlux.member_tx?(dets, tx, id) ->
        raise IppanError, "Account \"#{id}\" not exists"

      byte_size(name) > @name_max_length ->
        raise IppanError, "Invalid name length"

      not Match.url?(image) ->
        raise IppanError, "Image is not a valid URL"

      map_size(extra) > 5 ->
        raise IppanError, "Invalid extra key size"

      @max_services != 0 and @max_services <= Stats.services(stats) ->
        raise IppanError, "Total services register exceeded"

      PayService.exists?(db_ref, id) ->
        raise IppanError, "Already exists service: #{id}"

      true ->
        extra
        |> MapUtil.only(~w(only_auth min_amount summary))
        |> MapUtil.validate_bytes_range("summary", 1..255)
        |> MapUtil.validate_integer("min_amount")
        |> MapUtil.validate_value("min_amount", :gt, 0)

        price = EnvStore.service_price()

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
    end
  end

  def update(%{id: account_id, size: size, validator: %{fa: fa, fb: fb}}, id, map)
      when is_map(map) do
    map
    |> MapUtil.validate_length("name", @name_max_length)
    |> MapUtil.validate_url("image")

    extra = Map.drop(map, ["name", "image"])

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

      true ->
        :ok
    end
  end

  def subscribe(
        %{id: account_id, size: size, validator: %{fa: fa, fb: fb}},
        service_id,
        token_id,
        extra
      )
      when is_map(extra) do
    db_ref = :persistent_term.get(:main_conn)
    token = Token.get(token_id)

    cond do
      account_id == service_id ->
        raise IppanError, "Ilegal subscription"

      not Token.has_prop?(token, "stream") ->
        raise IppanError, "Stream property missing in #{token_id}"

      true ->
        case PayService.get(db_ref, service_id) do
          nil ->
            raise IppanError, "Service ID not exists"

          %{extra: service_extra} ->
            cond do
              SubPay.has?(db_ref, service_id, account_id, token_id) ->
                raise IppanError, "Already subscribed"

              true ->
                only_auth = Map.get(service_extra, "only_auth", false)
                min_amount = Map.get(service_extra, "min_amount", 0)

                extra
                |> MapUtil.validate_integer("exp")
                |> MapUtil.validate_integer("max_amount")
                |> MapUtil.validate_value("exp", :gt, 0)
                |> MapUtil.validate_value("max_amount", :gte, min_amount)

                fees = Utils.calc_fees(fa, fb, size)

                BalanceTrace.new(account_id)
                |> BalanceTrace.auth!(token_id, only_auth)
                |> BalanceTrace.requires!(@token, fees)
                |> BalanceTrace.output()
            end
        end
    end
  end

  def unsubscribe(%{id: account_id}, service_id) do
    db_ref = :persistent_term.get(:main_conn)

    unless SubPay.has?(db_ref, service_id, account_id) or
             SubPay.has?(db_ref, account_id, service_id),
           do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end

  def unsubscribe(%{id: account_id}, service_id, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    unless SubPay.has?(db_ref, service_id, account_id, token_id) or
             SubPay.has?(db_ref, account_id, service_id, token_id),
           do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end
end
