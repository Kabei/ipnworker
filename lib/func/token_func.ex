defmodule Ippan.Func.Token do
  alias Ippan.{Token, Utils}
  require BalanceStore
  require Sqlite
  require Token

  @app Mix.Project.config()[:app]
  @max_number 1_000_000_000_000_000_000_000_000_000
  @token Application.compile_env(@app, :token)
  @max_tokens Application.compile_env(@app, :max_tokens)

  def new(
        %{id: account_id},
        id,
        owner_id,
        name,
        decimal,
        symbol,
        max_supply \\ 0,
        opts \\ %{}
      )
      when byte_size(id) <= 10 and byte_size(name) <= 100 and decimal in 0..18 and
             byte_size(symbol) in 0..5 and max_supply >= 0 and max_supply <= @max_number do
    map_filter =
      opts
      |> Map.take(Token.optionals())

    db_ref = :persistent_term.get(:main_conn)

    cond do
      not Match.token?(id) ->
        raise IppanError, "Invalid token ID"

      not Match.account?(owner_id) ->
        raise IppanError, "Invalid owner argument"

      map_filter != opts ->
        raise IppanError, "Invalid option arguments"

      Token.exists?(id) ->
        raise IppanError, "Token already exists"

      @max_tokens <= Token.total() ->
        raise IppanError, "Maximum tokens exceeded"

      true ->
        price = EnvStore.token_price()

        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_url(:avatar)
        |> MapUtil.validate_any(:opts, Token.props())

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
      )
      when byte_size(id) <= 10 do
    map_filter = Map.take(opts, Token.editable())
    db_ref = :persistent_term.get(:main_conn)

    cond do
      map_size(opts) == 0 or map_filter != opts ->
        raise IppanError, "Invalid option field"

      not Token.owner?(id, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        fees = Utils.calc_fees(fa, fb, size)

        bt =
          BalanceTrace.new(account_id)
          |> BalanceTrace.requires!(@token, fees)

        MapUtil.to_atoms(map_filter)
        |> MapUtil.validate_length_range(:name, 1..100)
        |> MapUtil.validate_url(:avatar)
        |> MapUtil.validate_account(:owner)

        BalanceTrace.output(bt)
    end
  end

  def delete(%{id: account_id}, id) when byte_size(id) <= 10 do
    db_ref = :persistent_term.get(:main_conn)
    supply = TokenSupply.new(id)

    cond do
      TokenSupply.get(supply) != 0 ->
        raise IppanError, "Token is in use"

      not Token.owner?(id, account_id) ->
        raise IppanError, "Invalid owner"

      true ->
        :ok
    end
  end
end
