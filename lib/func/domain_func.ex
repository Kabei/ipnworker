defmodule Ippan.Func.Domain do
  alias Ippan.{Domain, Utils}
  require Domain
  require Sqlite
  require BalanceStore

  @app Mix.Project.config()[:app]
  @max_fullname_size 255
  @token Application.compile_env(@app, :token)

  def new(
        %{
          id: account_id,
          dets: dets,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        name,
        owner,
        days,
        opts \\ %{}
      )
      when byte_size(name) <= @max_fullname_size and
             days > 0 do
    map_filter = Map.take(opts, Domain.optionals())
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Match.ippan_domain?(name) ->
        raise IppanError, "Invalid domain name"

      map_filter != opts ->
        raise IppanError, "Invalid options parameter"

      not Match.account?(owner) ->
        raise IppanError, "Invalid owner argument"

      Domain.exists?(name) ->
        raise IppanError, "domain already exists"

      true ->
        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_url(:image)
        |> MapUtil.validate_email(:email)

        amount = Domain.price(name, days)
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, amount + fees)
        |> BalanceTrace.output()
    end
  end

  def update(
        %{
          id: account_id,
          dets: dets,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        name,
        opts \\ %{}
      ) do
    map_filter = Map.take(opts, Domain.editable())
    db_ref = :persistent_term.get(:main_conn)

    cond do
      map_size(opts) == 0 ->
        raise IppanError, "options is empty"

      map_filter != opts ->
        raise IppanError, "Invalid option field"

      not Domain.owner?(name, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_account(:owner)
        |> MapUtil.validate_url(:image)
        |> MapUtil.validate_email(:email)

        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def delete(%{id: account_id}, name) do
    db_ref = :persistent_term.get(:main_conn)

    unless Domain.owner?(name, account_id) do
      raise IppanError, "Invalid owner"
    end
  end

  def renew(%{id: account_id, dets: dets}, name, days)
      when is_integer(days) and days > 0 do
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Domain.owner?(name, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        amount = Domain.price(name, days)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, amount)
        |> BalanceTrace.output()
    end
  end
end
