defmodule Ippan.Funx.Service do
  require BalanceStore
  alias Ippan.Utils
  require Sqlite

  @app Mix.Project.config()[:app]
  @max_services Application.compile_env(@app, :max_services, 0)

  def new(source = %{id: account_id, round: round_id}, id, name, image, extra) do
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(:balance)
    price = EnvStore.service_price()
    stats = Stats.new()

    cond do
      @max_services != 0 and @max_services <= Stats.services(stats) ->
        :error

      BalanceStore.pay_burn(account_id, price) == :error ->
        :error

      true ->
        db_ref = :persistent_term.get(:main_conn)
        PayService.create(db_ref, id, name, image, extra, round_id)
        Stats.count_services(stats, 1)
    end
  end

  def update(
        source = %{
          id: account_id,
          round: round_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        id,
        map
      ) do
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(:balance)
    fees = Utils.calc_fees(fa, fb, size)
    db_ref = :persistent_term.get(:main_conn)

    case PayService.get(db_ref, id) do
      nil ->
        :error

      %{name: current_name, image: current_image, extra: current_extra} ->
        case BalanceStore.pay_fee(account_id, vOwner, fees) do
          :error ->
            :error

          _ ->
            name = Map.get(map, "name", current_name)
            image = Map.get(map, "image", current_image)

            extra =
              Map.drop(map, ["name", "image"])
              |> Map.merge(current_extra)

            PayService.update(
              db_ref,
              %{
                "name" => name,
                "image" => image,
                "extra" => CBOR.encode(extra),
                "updated_at" => round_id
              },
              id
            )
        end
    end
  end

  def delete(_source, id) do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not PayService.exists?(db_ref, id) ->
        :error

      true ->
        PayService.delete(db_ref, id)
        stats = Stats.new()
        Stats.count_services(stats, -1)
    end
  end

  def subscribe(
        source = %{
          id: account_id,
          round: round_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        service_id,
        token_id,
        extra
      ) do
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(:balance)
    fees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_fee(account_id, vOwner, fees) do
      :error ->
        :error

      _ ->
        db_ref = :persistent_term.get(:main_conn)

        SubPay.subscribe(
          db_ref,
          service_id,
          account_id,
          token_id,
          extra,
          round_id
        )
    end
  end

  def unsubscribe(%{id: account_id}, service_id) do
    db_ref = :persistent_term.get(:main_conn)
    SubPay.unsubscribe(db_ref, service_id, account_id)
  end

  def unsubscribe(%{id: account_id}, service_id, token_id) do
    db_ref = :persistent_term.get(:main_conn)
    SubPay.unsubscribe(db_ref, service_id, account_id, token_id)
  end
end
