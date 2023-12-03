defmodule Ippan.Ecto.Payments do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3, join: 5]
  alias Ippan.{Ecto.Round, Utils}
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"
  schema "payments" do
    field(:from, :binary)
    field(:nonce, :decimal)
    field(:to, :binary)
    field(:round, :integer)
    field(:type, :integer)
    field(:token, :binary)
    field(:amount, :decimal)
  end

  @select ~w(from nonce to round type token amount)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def all(params) do
    from(Payments)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_while(params)
    |> filter_type(params)
    |> filter_token(params)
    |> filter_range(params)
    |> filter_select(params)
    |> sort(params)
    |> Repo.all()
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

  defp filter_range(query, %{"dateEnd" => fin, "dateStart" => start}) do
    start = Utils.date_start_to_time(start)
    fin = Utils.date_end_to_time(fin)

    join(query, :inner, [p], r in Round, on: p.round == r.id)
    |> where([_p, r], r.timestamp >= ^start and r.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateEnd" => fin}) do
    fin = Utils.date_end_to_time(fin)

    join(query, :inner, [p], r in Round, on: p.round == r.id)
    |> where([_p, r], r.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateStart" => start}) do
    start = Utils.date_start_to_time(start)

    join(query, :inner, [p], r in Round, on: p.round == r.id)
    |> where([_p, r], r.timestamp >= ^start)
  end

  defp filter_range(query, _), do: query

  defp filter_while(query, %{"target" => address}) do
    where(query, [p], p.from == ^address or p.to == ^address)
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

  defp filter_type(query, _), do: query

  defp filter_token(query, %{"token" => token}) do
    where(query, [p], p.token == ^token)
  end

  defp filter_token(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [p], asc: p.round)

  defp sort(query, %{"sort" => "from"}),
    do: order_by(query, [p], desc: p.round, asc: p.from, asc: p.nonce)

  defp sort(query, _), do: order_by(query, [p], desc: p.round)
end
