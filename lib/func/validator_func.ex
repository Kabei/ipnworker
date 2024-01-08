defmodule Ippan.Func.Validator do
  import Guards
  alias Ippan.{Utils, Validator}
  require Validator
  require Sqlite
  require BalanceStore

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @max_validators Application.compile_env(@app, :max_validators)
  @max_fees 1_000_000_000_000

  def join(
        %{id: account_id},
        hostname,
        port,
        owner_id,
        name,
        pubkey,
        net_pubkey,
        fa \\ 0,
        fb \\ 1,
        opts \\ %{}
      )
      when byte_size(name) <= 20 and between_size(hostname, 4, 100) and is_integer(fa) and
             is_integer(fb) and
             check_port(port) do
    map_filter = Map.take(opts, Validator.optionals())
    pubkey = Fast64.decode64(pubkey)
    net_pubkey = Fast64.decode64(net_pubkey)
    db_ref = :persistent_term.get(:main_conn)
    next_id = Validator.next_id()

    cond do
      fa < 0 or fa > @max_fees or fb < 1 or fb > @max_fees ->
        raise IppanError, "Invalid fees"

      byte_size(net_pubkey) > 1138 ->
        raise IppanError, "Invalid net_pubkey size #{byte_size(net_pubkey)}"

      byte_size(pubkey) > 897 ->
        raise IppanError, "Invalid pubkey size"

      not Match.account?(owner_id) ->
        raise IppanError, "Invalid owner"

      map_filter != opts ->
        raise IppanError, "Invalid options parameter"

      not Match.hostname?(hostname) and not Match.ipv4?(hostname) ->
        raise IppanError, "Invalid hostname"

      Validator.exists_host?(hostname) ->
        raise IppanError, "Validator already exists"

      @max_validators <= next_id ->
        raise IppanError, "Maximum validators exceeded"

      true ->
        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_url(:avatar)

        price = Validator.calc_price(next_id)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, price)
        |> BalanceTrace.output()
    end
  end

  def update(
        %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        id,
        opts \\ %{}
      ) do
    map_filter = Map.take(opts, Validator.editable())
    db_ref = :persistent_term.get(:main_conn)

    cond do
      map_size(opts) == 0 or map_filter != opts ->
        raise IppanError, "Invalid option field"

      not Validator.owner?(id, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        bt =
          BalanceTrace.new(account_id)
          |> BalanceTrace.requires!(@token, fees)

        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_hostname_or_ip(:hostname)
        |> MapUtil.validate_length_range(:name, 1..20)
        |> MapUtil.validate_url(:avatar)
        |> MapUtil.validate_text(:class)
        |> MapUtil.validate_integer(:fa)
        |> MapUtil.validate_integer(:fb)
        |> MapUtil.validate_value(:fa, :gte, 0)
        |> MapUtil.validate_value(:fb, :gte, 1)
        |> MapUtil.transform(:pubkey, fn x ->
          case Fast64.decode64(x) do
            j when byte_size(j) > 897 ->
              raise IppanError, "Invalid pubkey"

            j ->
              j
          end
        end)
        |> MapUtil.transform(:net_pubkey, fn x ->
          case Fast64.decode64(x) do
            j when byte_size(j) > 1138 ->
              raise IppanError, "Invalid net_pubkey"

            j ->
              j
          end
        end)

        BalanceTrace.output(bt)
    end
  end

  def active(%{id: account_id, size: size, validator: %{fa: fa, fb: fb}}, id, active)
      when is_boolean(active) do
    db_ref = :persistent_term.get(:main_conn)
    v = Validator.get(id)

    cond do
      is_nil(v) ->
        raise IppanError, "Validator #{id} not exists"

      v.active == active ->
        raise IppanError, "Property already has the same value"

      v.owner != account_id ->
        raise IppanError, "Invalid owner"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def leave(%{id: account_id}, id) do
    db_ref = :persistent_term.get(:main_conn)

    unless Validator.owner?(id, account_id) do
      raise IppanError, "Invalid owner"
    end
  end

  def env_put(
        %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        id,
        name,
        _value
      )
      when byte_size(name) in 1..30 do
    db_ref = :persistent_term.get(:main_conn)
    validator = Validator.get(id)

    cond do
      size > 1024 ->
        raise IppanError, "Invalid tx size"

      map_size(validator.env) >= 10 ->
        raise IppanError, "Invalid variables map size"

      validator.owner != account_id ->
        raise IppanError, "Invalid owner"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end

  def env_delete(
        %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb}
        },
        id,
        name
      ) do
    db_ref = :persistent_term.get(:main_conn)
    validator = Validator.get(id)

    cond do
      validator.owner != account_id and
          validator.owner != EnvStore.owner() ->
        raise IppanError, "Invalid owner"

      not Map.has_key?(validator.env, name) ->
        raise IppanError, "#{name} not exists"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        BalanceTrace.new(account_id)
        |> BalanceTrace.requires!(@token, fees)
        |> BalanceTrace.output()
    end
  end
end
