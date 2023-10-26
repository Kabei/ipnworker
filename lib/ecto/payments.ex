defmodule Ippan.Ecto.Payments do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"
  schema "payments" do
    field(:ix, :integer)
    field(:block, :integer)
    field(:type, :integer)
    field(:from, :binary)
    field(:to, :binary)
    field(:token, :binary)
    field(:amount, :integer)
  end

  @select ~w(ix block type from to token amount)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def by(block, ix) do
    from(p in Payments,
      where: p.ix == ^ix and p.block == ^block,
      order_by: [desc: p.block, asc: p.ix]
    )
    |> filter_select()
    |> Repo.all()
  end

  def all(params) do
    from(Payments)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_below(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
  end

  defp filter_select(query) do
    select(query, [p], map(p, @select))
  end

  defp filter_below(query, %{"below" => id}) do
    where(query, [p], p.block < ^id)
  end

  defp filter_below(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [p], asc: p.block, asc: p.ix)
  defp sort(query, _), do: order_by(query, [p], desc: p.block, asc: p.ix)
end
