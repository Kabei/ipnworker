defmodule Ippan.Ecto.Payments do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3, join: 5]
  alias Ippan.{Ecto.Round, Token, Utils}
  alias Ipnworker.Repo
  alias __MODULE__
  require Token
  require Sqlite

  @primary_key false
  @schema_prefix "history"
  schema "payments" do
    field(:from, :string)
    field(:nonce, :decimal)
    field(:to, :string)
    field(:round, :integer)
    field(:type, :integer)
    field(:token, :string)
    field(:amount, :decimal)
  end

  @select ~w(from nonce to round type token amount)a
  @token_fields ~w(decimal symbol)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def all(params) do
    from(Payments)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_while(params)
    |> filter_type(params)
    |> filter_token(params)
    |> filter_range(params)
    |> filter_date(params)
    |> filter_select(params)
    |> sort(params)
    |> Repo.all()
    |> data()
  end

  defp filter_select(query, %{"times" => _}) do
    join(query, :inner, [p], r in Round, on: p.round == r.id)
    |> select([p, r], %{
      amount: p.amount,
      from: p.from,
      nonce: p.nonce,
      to: p.to,
      round: p.round,
      type: p.type,
      timestamp: r.timestamp,
      token: p.token
    })
  end

  defp filter_select(query, _) do
    select(query, [p], map(p, @select))
  end

  defp data(results) do
    db_ref = :persistent_term.get(:main_conn)

    Enum.filter(results, fn
      %{token: nil} -> false
      %{token: _token} -> true
    end)
    |> Enum.map(fn x ->
      token = Token.get(x.token)

      Map.merge(x, Map.take(token, @token_fields))
      |> MapUtil.drop_nils()
    end)
  end

  defp filter_range(query, %{"round" => id}) do
    where(query, [p], p.round == ^id)
  end

  defp filter_range(query, %{"roundEnd" => fin, "roundStart" => start}) do
    where(query, [p], p.round >= ^start and p.round <= ^fin)
  end

  defp filter_range(query, %{"roundStart" => id}) do
    where(query, [p], p.round >= ^id)
  end

  defp filter_range(query, %{"roundEnd" => id}) do
    where(query, [p], p.round <= ^id)
  end

  defp filter_range(query, _), do: query

  defp filter_date(query, %{"dateEnd" => fin, "dateStart" => start, "times" => _}) do
    start = Utils.date_start_to_time(start)
    fin = Utils.date_end_to_time(fin)

    where(query, [_p, r], r.timestamp >= ^start and r.timestamp <= ^fin)
  end

  defp filter_date(query, %{"dateEnd" => fin, "times" => _}) do
    fin = Utils.date_end_to_time(fin)

    where(query, [_p, r], r.timestamp <= ^fin)
  end

  defp filter_date(query, %{"dateStart" => start, "times" => _}) do
    start = Utils.date_start_to_time(start)

    where(query, [_p, r], r.timestamp >= ^start)
  end

  defp filter_date(query, _), do: query

  defp filter_while(query, %{"target" => address}) do
    where(query, [p], p.from == ^address or p.to == ^address)
  end

  defp filter_while(query, %{"in" => address}) do
    where(query, [p], p.to == ^address and p.amount > 0)
  end

  defp filter_while(query, %{"out" => address}) do
    where(query, [p], p.to == ^address and p.amount < 0)
  end

  defp filter_while(query, %{"from" => address, "nonce" => nonce}) do
    where(query, [p], p.from == ^address and p.nonce == ^nonce)
  end

  defp filter_while(query, %{"from" => address}) do
    where(query, [p], p.from == ^address)
  end

  defp filter_while(query, %{"to" => address, "nonce" => nonce}) do
    where(query, [p], p.to == ^address and p.nonce == ^nonce)
  end

  defp filter_while(query, %{"to" => address}) do
    where(query, [p], p.to == ^address)
  end

  defp filter_while(query, _), do: query

  defp filter_type(query, %{"type" => type}) do
    where(query, [p], p.type == ^type)
  end

  defp filter_type(query, %{"types" => types}) do
    array = get_array_of_types(types)
    where(query, [p], p.type in ^array)
  end

  defp filter_type(query, %{"ntypes" => ntypes}) do
    array = get_array_of_types(ntypes)

    where(query, [p], p.type not in ^array)
  end

  defp filter_type(query, _), do: query

  defp filter_token(query, %{"token" => token}) do
    where(query, [p], p.token == ^token)
  end

  defp filter_token(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [p], asc: p.round)

  defp sort(query, %{"sort" => "from"}),
    do: order_by(query, [p], desc: p.round, asc: p.from, asc: p.nonce)

  defp sort(query, _), do: order_by(query, [p], desc: p.round)

  # Util functions
  defp get_array_of_types(types) do
    String.split(types, ",", trim: true)
    |> Enum.map(&String.to_integer(&1))
  end
end
