defmodule Ippan.Funx.Validator do
  alias Ippan.{Utils, Validator}
  alias Phoenix.PubSub
  require Validator
  require Sqlite
  require BalanceStore
  require Logger

  @app Mix.Project.config()[:app]
  @pubsub :pubsub
  @max_validators Application.compile_env(@app, :max_validators)
  @topic "validator"

  def join(
        source = %{id: account_id, round: round_id},
        hostname,
        port,
        owner_id,
        name,
        pubkey,
        net_pubkey,
        fa \\ 0,
        fb \\ 1,
        opts \\ %{}
      ) do
    db_ref = :persistent_term.get(:main_conn)
    next_id = Validator.next_id()

    cond do
      Validator.exists_host?(hostname) ->
        :error

      @max_validators <= next_id ->
        :error

      true ->
        map_filter = Map.take(opts, Validator.optionals())
        pubkey = Fast64.decode64(pubkey)
        net_pubkey = Fast64.decode64(net_pubkey)
        db = DetsPlux.get(:balance)
        tx = DetsPlux.tx(db, :balance)
        price = Validator.calc_price(next_id)

        case BalanceStore.pay_burn(account_id, price) do
          :error ->
            :error

          _ ->
            next_id = Validator.next_id()

            validator =
              %Validator{
                id: next_id,
                hostname: hostname,
                port: port,
                name: name,
                pubkey: pubkey,
                net_pubkey: net_pubkey,
                owner: owner_id,
                fa: fa,
                fb: fb,
                created_at: round_id,
                updated_at: round_id
              }
              |> Map.merge(MapUtil.to_atoms(map_filter))

            Validator.insert(Validator.to_list(validator))

            event = %{"event" => "validator.new", "data" => Validator.to_text(validator)}
            PubSub.broadcast(@pubsub, @topic, event)
        end
    end
  end

  def update(
        source = %{id: account_id, size: size, validator: %{fa: fa, fb: fb}, round: round_id},
        id,
        opts
      ) do
    map_filter = Map.take(opts, Validator.editable())
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_burn(account_id, fees) do
      :error ->
        :error

      _ ->
        # transform to binary
        fun = fn x -> Base.decode64!(x) end

        prev_map =
          MapUtil.to_atoms(map_filter)
          |> Map.put(:updated_at, round_id)

        map =
          prev_map
          |> MapUtil.transform(:pubkey, fun)
          |> MapUtil.transform(:net_pubkey, fun)

        db_ref = :persistent_term.get(:main_conn)
        Validator.update(map, id)

        event = %{"event" => "validator.update", "data" => %{"id" => id, "args" => prev_map}}
        PubSub.broadcast(@pubsub, @topic, event)
    end
  end

  def active(
        source = %{
          id: account_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner},
          round: round_id
        },
        id,
        active
      ) do
    db_ref = :persistent_term.get(:main_conn)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_fee(account_id, vOwner, fees) do
      :error ->
        :error

      _ ->
        if active do
          Validator.enable(id, round_id)
        else
          Validator.disable(id, round_id)
        end

        event = %{"event" => "validator.active", "data" => %{"id" => id, "active" => active}}
        PubSub.broadcast(@pubsub, @topic, event)
    end
  end

  def leave(_source, id) do
    db_ref = :persistent_term.get(:main_conn)
    Validator.delete(id)

    event = %{"event" => "validator.leave", "data" => id}
    PubSub.broadcast(@pubsub, @topic, event)
  end

  def env_put(
        source = %{
          id: account_id,
          round: round_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        id,
        name,
        value
      ) do
    db_ref = :persistent_term.get(:main_conn)
    validator = Validator.get(id)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case is_nil(validator) do
      true ->
        :error

      _false ->
        case BalanceStore.pay_fee(account_id, vOwner, fees) do
          :error ->
            :error

          _ ->
            result = Map.put(validator.env, name, value)
            map = %{env: CBOR.encode(result), updated_at: round_id}
            Validator.update(map, id)
        end
    end
  end

  def env_delete(
        source = %{
          id: account_id,
          round: round_id,
          size: size,
          validator: %{fa: fa, fb: fb, owner: vOwner}
        },
        id,
        name
      ) do
    db_ref = :persistent_term.get(:main_conn)
    validator = Validator.get(id)
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case is_nil(validator) do
      true ->
        :error

      _false ->
        case BalanceStore.pay_fee(account_id, vOwner, fees) do
          :error ->
            :error

          _ ->
            result = Map.delete(validator.env, name)
            map = %{env: CBOR.encode(result), updated_at: round_id}
            Validator.update(map, id)
        end
    end
  end
end
