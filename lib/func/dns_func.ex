defmodule Ippan.Func.Dns do
  alias Ippan.{Domain, DNS}
  require Sqlite
  require DNS
  require Domain
  require BalanceStore

  @token Application.compile_env(:ipnworker, :token)
  @fullname_max_size 255
  @type_range [1, 2, 6, 15, 16, 28]
  @data_range 1..255
  @ttl_range 0..2_147_483_648

  def new(%{id: account_id, size: size}, fullname, type, data, ttl)
      when byte_size(fullname) <= @fullname_max_size and
             type in @type_range and
             byte_size(data) in @data_range and
             ttl in @ttl_range do
    {_subdomain, domain} = Domain.split(fullname)
    dns_type = DNS.type_to_alpha(type)
    db_ref = :persistent_term.get(:asset_conn)

    cond do
      not Match.hostname?(fullname) ->
        raise IppanError, "Invalid hostname"

      not match?(
        {_, _, _, _, _value},
        :dnslib.resource(~c"#{fullname} IN #{ttl} #{dns_type} #{data}")
      ) ->
        raise IppanError, "DNS resource format error"

      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, size)
        |> BalanceTrace.output()
    end
  end

  def update(%{id: account_id}, fullname, dns_hash16, params) do
    map_filter = Map.take(params, DNS.editable())

    {_subdomain, domain} = Domain.split(fullname)

    dns_hash = Base.decode16!(dns_hash16, case: :mixed)

    fees = EnvStore.network_fee()

    db_ref = :persistent_term.get(:asset_conn)

    dns =
      DNS.get(domain, dns_hash)

    cond do
      map_filter == %{} ->
        raise IppanError, "Invalid optional arguments"

      map_filter != params ->
        raise IppanError, "Invalid optional arguments"

      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid owner"

      not match?(
        {_, _, _, _, _value},
        :dnslib.resource(~c"#{fullname} IN #{dns.ttl} #{dns.type} #{dns.data}")
      ) ->
        raise ArgumentError, "DNS resource format error"

      true ->
        bt =
          BalanceTrace.new(account_id)
          |> BalanceTrace.requires!(@token, fees)

        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_range(:ttl, @ttl_range)
        |> MapUtil.validate_bytes_range(:data, @data_range)

        BalanceTrace.output(bt)
    end
  end

  def delete(%{id: account_id}, fullname)
      when byte_size(fullname) <= @fullname_max_size do
    {_subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:asset_conn)

    unless Domain.owner?(domain, account_id) do
      raise IppanError, "Invalid Owner"
    end
  end

  def delete(%{id: account_id}, fullname, type)
      when type in @type_range do
    {_subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:asset_conn)

    unless Domain.owner?(domain, account_id) do
      raise IppanError, "Invalid Owner"
    end
  end

  def delete(%{id: account_id}, fullname, hash16)
      when byte_size(hash16) == 32 do
    {_subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:asset_conn)

    cond do
      not Match.base16(hash16) ->
        raise IppanError, "Invalid hash"

      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid Owner"

      true ->
        nil
    end
  end
end
