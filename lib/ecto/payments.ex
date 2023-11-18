defmodule Ippan.Ecto.Payments do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"
  schema "payments" do
    field(:from, :binary)
    field(:nonce, :integer)
    field(:to, :binary)
    field(:round, :integer)
    field(:type, :integer)
    field(:token, :binary)
    field(:amount, :integer)
  end

  @select ~w(from nonce to round type token amount)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def by(address, nonce) do
    from(p in Payments, where: p.from == ^address and p.nonce == ^nonce)
    |> filter_select()
    |> Repo.all()
  end

  def all(params) do
    from(Payments)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_while(params)
    |> filter_type(params)
    |> filter_round(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
  end

  defp filter_select(query) do
    select(query, [p], map(p, @select))
  end

  defp filter_round(query, %{"round" => id}) do
    where(query, [p], p.round == ^id)
  end

  defp filter_round(query, %{"attach" => id}) do
    where(query, [p], p.round <= ^id)
  end

  defp filter_round(query, _), do: query

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

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [p], asc: p.round)
  defp sort(query, %{"sort" => "from"}), do: order_by(query, [p], desc: p.round, asc: p.from, asc: p.nonce)
  defp sort(query, _), do: order_by(query, [p], desc: p.round)
end
