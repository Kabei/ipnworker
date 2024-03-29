defmodule Ippan.Func.Dns do
  alias Ippan.{Domain, DNS, Utils}
  require Sqlite
  require DNS
  require Domain
  require BalanceStore

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @fullname_max_size 255
  @type_range [1, 2, 6, 15, 16, 28]
  @data_range 1..255
  @ttl_range 0..2_147_483_648

  def new(
        %{id: account_id, dets: dets, size: size, validator: %{fa: fa, fb: fb}},
        fullname,
        type,
        data,
        ttl
      )
      when byte_size(fullname) <= @fullname_max_size and
             type in @type_range and
             byte_size(data) in @data_range and
             ttl in @ttl_range do
    {_subdomain, domain} = Domain.split(fullname)
    dns_type = DNS.type_to_alpha(type)
    db_ref = :persistent_term.get(:main_conn)

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
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id, dets.balance)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def update(
        %{id: account_id, dets: dets, size: size, validator: %{fa: fa, fb: fb}},
        fullname,
        dns_hash16,
        params
      ) do
    opts = Map.take(params, DNS.editable())

    {_subdomain, domain} = Domain.split(fullname)

    dns_hash = Base.decode16!(dns_hash16, case: :mixed)

    db_ref = :persistent_term.get(:main_conn)

    [_, _, type, data, ttl, _hash] =
      DNS.get(domain, dns_hash)

    cond do
      map_size(opts) == 0 or opts != params ->
        raise IppanError, "Invalid optional arguments"

      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid owner"

      not match?(
        {_, _, _, _, _value},
        :dnslib.resource(
          ~c"#{fullname} IN #{Map.get(opts, "ttl", ttl)} #{DNS.type_to_alpha(type)} #{Map.get(opts, "data", data)}"
        )
      ) ->
        raise ArgumentError, "DNS resource format error"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        bt =
          BalanceTrace.new(account_id, dets.balance)
          |> BalanceTrace.requires!(@token, fees)

        MapUtil.to_atoms(opts)
        |> MapUtil.validate_range(:ttl, @ttl_range)
        |> MapUtil.validate_bytes_range(:data, @data_range)

        BalanceTrace.output(bt)
    end
  end

  def delete(%{id: account_id}, fullname)
      when byte_size(fullname) <= @fullname_max_size do
    {subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid Owner"

      not DNS.exists?(domain, subdomain) ->
        raise IppanError, "Not exists"

      true ->
        nil
    end
  end

  def delete(%{id: account_id}, fullname, type)
      when type in @type_range do
    {subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid Owner"

      not DNS.exists_type?(domain, subdomain, type) ->
        raise IppanError, "Not exists"

      true ->
        nil
    end
  end

  def delete(%{id: account_id}, fullname, hash16)
      when byte_size(hash16) == 32 do
    {subdomain, domain} = Domain.split(fullname)
    db_ref = :persistent_term.get(:main_conn)
    hash = Base.decode16!(hash16, case: :mixed)

    cond do
      not Domain.owner?(domain, account_id) ->
        raise IppanError, "Invalid Owner"

      not DNS.exists_hash?(domain, subdomain, hash) ->
        raise IppanError, "Not exists"

      true ->
        nil
    end
  end
end
