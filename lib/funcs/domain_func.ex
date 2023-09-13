defmodule Ippan.Func.Domain do
  alias Ippan.Domain
  alias Ippan.Utils
  require SqliteStore
  require BalanceStore

  @max_fullname_size 255
  @token Application.compile_env(:ipnworker, :token)

  def new(
        %{
          id: account_id,
          conn: conn,
          stmts: stmts,
          dets: dets,
          size: size,
          validator: validator
        },
        domain_name,
        owner,
        days,
        opts \\ %{}
      )
      when byte_size(domain_name) <= @max_fullname_size and
             days > 0 do
    map_filter = Map.take(opts, Domain.optionals())

    cond do
      not Match.ippan_domain?(domain_name) ->
        raise IppanError, "Invalid domain name"

      map_filter != opts ->
        raise IppanError, "Invalid options parameter"

      not Match.account?(owner) ->
        raise IppanError, "Invalid owner argument"

      SqliteStore.exists?(conn, stmts, "exists_domain", domain_name) ->
        raise IppanError, "domain already exists"

      true ->
        amount = Domain.price(domain_name, days)

        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_url(:avatar)
        |> MapUtil.validate_email(:email)

        fee_amount = Utils.calc_fees!(validator.fee_type, validator.fee, amount, size)

        case BalanceStore.has_balance?(dets, {account_id, @token}, amount + fee_amount) do
          true ->
            :ok

          _ ->
            raise IppanError, "Insufficient balance"
        end
    end
  end

  def update(
        %{id: account_id, conn: conn, stmts: stmts, dets: dets, size: size},
        name,
        opts \\ %{}
      ) do
    map_filter = Map.take(opts, Domain.editable())

    cond do
      opts == %{} ->
        raise IppanError, "options is empty"

      map_filter != opts ->
        raise IppanError, "Invalid option field"

      not SqliteStore.exists?(conn, stmts, "owner_domain", [name, account_id]) ->
        raise IppanError, "Invalid owner"

      not BalanceStore.has_balance?(dets, {account_id, @token}, size) ->
        raise IppanError, "Insufficient balance"

      true ->
        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_account(:owner)
        |> MapUtil.validate_url(:avatar)
        |> MapUtil.validate_email(:email)

        :ok
    end
  end

  def delete(%{id: account_id, conn: conn, stmts: stmts}, name) do
    cond do
      not SqliteStore.exists?(conn, stmts, "owner_domain", [name, account_id]) ->
        raise IppanError, "Invalid owner"

      true ->
        :ok
    end
  end

  def renew(%{id: account_id, conn: conn, stmts: stmts, dets: dets}, name, days)
      when is_integer(days) and days > 0 do
    amount = Domain.price(name, days)

    cond do
      not SqliteStore.exists?(conn, stmts, "owner_domain", [name, account_id]) ->
        raise IppanError, "Invalid owner"

      not BalanceStore.has_balance?(dets, {account_id, @token}, amount) ->
        raise IppanError, "Insufficient balance"

      true ->
        :ok
    end
  end
end