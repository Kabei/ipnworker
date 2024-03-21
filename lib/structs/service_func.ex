defmodule Ippan.Func.Service do
  require BalanceStore
  alias Ippan.{Token, Utils}
  require Sqlite
  require Token

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @name_max_length 50
  @max_services Application.compile_env(@app, :max_services, 0)
  @max_amount 1_000_000_000_000_000_000
  @skey "services"

  def new(
        %{id: account_id, dets: dets},
        id,
        name,
        owner,
        image,
        descrip,
        extra \\ %{}
      )
      when is_map(extra) do
    db_ref = :persistent_term.get(:main_conn)
    stats = Stats.new(dets.stats)

    cond do
      not Match.service?(id) ->
        raise IppanError, "Invalid ID"

      not Match.account?(owner) ->
        raise IppanError, "Invalid Owner"

      byte_size(name) > @name_max_length ->
        raise IppanError, "Invalid name length"

      byte_size(descrip) > 255 ->
        raise IppanError, "Invalid description length"

      not Match.url?(image) ->
        raise IppanError, "Image is not a valid URL"

      map_size(extra) > 5 ->
        raise IppanError, "Invalid extra key size"

      @max_services != 0 and @max_services <= Stats.get(stats, @skey) ->
        raise IppanError, "Total services register exceeded"

      PayService.exists?(db_ref, id) ->
        raise IppanError, "Already exists service: #{id}"

      true ->
        extra
        |> MapUtil.only(~w(only_auth min_amount))
        |> MapUtil.validate_integer("min_amount")
        |> MapUtil.validate_value("min_amount", :gt, 0)

        price = EnvStore.service_price()

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
    end
  end

  def update(%{id: account_id, dets: dets, size: size, validator: %{fa: fa, fb: fb}}, id, map)
      when is_map(map) do
    map
    |> MapUtil.validate_length("name", @name_max_length)
    |> MapUtil.validate_length_range("descrip", 0..255)
    |> MapUtil.validate_account("owner")
    |> MapUtil.validate_url("image")
    |> MapUtil.validate(
      fn
        x when is_map(x) and map_size(x) <= 5 -> true
        _x -> false
      end,
      "Invalid extra parameter"
    )

    db_ref = :persistent_term.get(:main_conn)

    cond do
      not PayService.owner?(db_ref, id, account_id) ->
        raise IppanError, "Unauthorized"

      not PayService.exists?(db_ref, id) ->
        raise IppanError, "Not exists service: #{id}"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
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

  def pay(%{id: account_id, dets: dets}, service_id, token_id, amount)
      when amount in 1..@max_amount do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Match.service?(service_id) ->
        raise(IppanError, "Invalid service ID")

      not PayService.exists?(db_ref, service_id) ->
        raise(IppanError, "Service does not exists")

      true ->
        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(token_id, amount)
        |> BalanceTrace.output()
    end
  end

  def stream(%{dets: dets}, service_id, payer, token_id, amount)
      when amount in 1..@max_amount do
    db_ref = :persistent_term.get(:main_conn)

    case SubPay.get(db_ref, service_id, payer, token_id) do
      nil ->
        raise IppanError, "Payment not authorized"

      %{
        every: every,
        extra: extra,
        spent: spent,
        div: interval
      } ->
        stats = Stats.new(dets.stats)
        expiry = Map.get(extra, "exp", 0)
        max_amount = Map.get(extra, "maxAmount", 0)
        max_spent = Map.get(extra, "maxSpent", 0)
        round_id = Stats.get(stats, "last_round")
        current_interval = div(round_id, every)

        cond do
          max_spent != 0 and
            spent > max_spent and
              interval == current_interval ->
            raise IppanError, "Exceeded limit spent"

          max_amount != 0 and amount > max_amount ->
            raise IppanError, "Exceeded max amount"

          expiry != 0 and expiry < round_id ->
            raise IppanError, "Subscription has expired"

          true ->
            BalanceTrace.new(payer, dets.balance)
            |> BalanceTrace.requires!(token_id, amount)
            |> BalanceTrace.output()
        end
    end
  end

  def withdraw(
        %{id: account_id, dets: dets, size: size, validator: %{fa: fa, fb: fb}},
        service_id,
        token_id,
        amount
      )
      when is_integer(amount) and amount > 0 do
    db_ref = :persistent_term.get(:main_conn)

    if not PayService.owner?(db_ref, service_id, account_id),
      do: raise(IppanError, "Unauthorized")

    fees = Utils.calc_fees(fa, fb, size)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, dets.balance)

    %{
      output:
        BalanceStore.multi_requires!(db, tx, [
          {BalanceStore.make(account_id, @token), fees},
          {BalanceStore.make(service_id, token_id), amount}
        ])
    }
  end

  def subscribe(
        %{id: account_id, dets: dets, size: size, validator: %{fa: fa, fb: fb}},
        service_id,
        token_id,
        every,
        extra \\ %{}
      )
      when is_map(extra) do
    db_ref = :persistent_term.get(:main_conn)

    case PayService.get(db_ref, service_id) do
      nil ->
        raise IppanError, "Service ID not exists"

      %{extra: service_extra} ->
        min_amount = Map.get(service_extra, "minAmount", 0)

        cond do
          SubPay.has?(db_ref, service_id, account_id, token_id) ->
            raise IppanError, "Already subscribed"

          every not in 0..10_000_000 ->
            raise IppanError, "Invalid every parameter, select a number between 0 and 10M"

          true ->
            only_auth = Map.get(service_extra, "onlyAuth", false)

            extra
            |> MapUtil.require(~w(maxAmount))
            |> MapUtil.only(~w(exp maxAmount maxSpent))
            |> Enum.each(fn
              {"maxAmount", max_amount} ->
                if max_amount not in 0..@max_amount,
                  do: raise(IppanError, "Invalid maxAmount parameter")

                if min_amount > max_amount, do: raise(IppanError, "Invalid maxAmount parameter")

              {key, value} when key in ~w(exp maxSpent) ->
                if is_integer(value) and value < 0,
                  do:
                    raise(
                      ArgumentError,
                      "Invalid #{key} parameter, must be integer greater than zero"
                    )

              x ->
                x
            end)

            fees = Utils.calc_fees(fa, fb, size)

            BalanceTrace.new(account_id, dets.balance)
            |> BalanceTrace.auth!(token_id, only_auth)
            |> BalanceTrace.requires!(@token, fees)
            |> BalanceTrace.output()
        end
    end
  end

  def unsubscribe(%{id: account_id}, service_id) do
    db_ref = :persistent_term.get(:main_conn)

    if not SubPay.has?(db_ref, service_id, account_id),
      do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end

  def unsubscribe(%{id: account_id}, service_id, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    if not SubPay.has?(db_ref, service_id, account_id, token_id),
      do: raise(IppanError, "#{account_id} has not subscription with #{service_id}")
  end

  def kick(%{id: account_id}, service_id, payer) do
    db_ref = :persistent_term.get(:main_conn)

    if not PayService.owner?(db_ref, service_id, account_id),
      do: raise(IppanError, "Unauthorized")

    if not SubPay.has?(db_ref, service_id, payer),
      do: raise(IppanError, "#{payer} has not subscription with #{service_id}")
  end

  def kick(%{id: account_id}, service_id, payer, token_id) do
    db_ref = :persistent_term.get(:main_conn)

    if not PayService.owner?(db_ref, service_id, account_id),
      do: raise(IppanError, "Unauthorized")

    if not SubPay.has?(db_ref, service_id, payer, token_id),
      do: raise(IppanError, "#{payer} has not subscription with #{service_id}")
  end
end
