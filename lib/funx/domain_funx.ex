defmodule Ippan.Funx.Domain do
  alias Ippan.{Domain, DNS, Utils}
  require BalanceStore
  require Sqlite
  require Domain
  require DNS

  @one_day 20_000

  def new(source = %{id: account_id, round: round_id}, name, owner, days, opts \\ %{}) do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      Domain.exists?(name) ->
        :error

      true ->
        db = DetsPlux.get(:balance)
        tx = DetsPlux.tx(db, :balance)
        price = Domain.price(name, days)

        case BalanceStore.pay_burn(account_id, price) do
          :error ->
            :error

          _ ->
            map_filter = Map.take(opts, Domain.optionals())

            domain =
              %Domain{
                name: name,
                owner: owner,
                created_at: round_id,
                renewed_at: round_id + days * @one_day,
                updated_at: round_id
              }
              |> Map.merge(MapUtil.to_atoms(map_filter))
              |> Domain.to_list()

            Domain.insert(domain)
        end
    end
  end

  def update(
        source = %{
          id: account_id,
          round: round_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        name,
        opts \\ %{}
      ) do
    map_filter = Map.take(opts, Domain.editable())
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_fee(account_id, vOwner, fees) do
      :error ->
        :error

      _ ->
        map =
          MapUtil.to_atoms(map_filter)
          |> Map.put(:updated_at, round_id)

        db_ref = :persistent_term.get(:main_conn)
        Domain.update(map, name)
    end
  end

  def delete(%{id: account_id}, name) do
    db_ref = :persistent_term.get(:main_conn)
    Domain.delete(name, account_id)
    DNS.delete(name)
  end

  def renew(source = %{id: account_id, round: round_id}, name, days) do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    price = Domain.price(name, days)

    case BalanceStore.pay_burn(account_id, price) do
      :error ->
        :error

      _ ->
        db_ref = :persistent_term.get(:main_conn)
        Domain.renew(name, account_id, days * @one_day, round_id)
    end
  end
end
