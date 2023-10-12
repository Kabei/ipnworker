defmodule Schema.Round do
  alias Schema.Round
  alias Ipnworker.Repo
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3]

  @primary_key false
  @schema_prefix "history"

  schema "rounds" do
    field(:id, :integer)
    field(:hash, :binary)
    field(:prev, :binary)
    field(:creator, :integer)
    field(:signature, :binary)
    field(:coinbase, :integer)
    field(:count, :integer)
    field(:tx_count, :integer)
    field(:size, :integer)
    field(:reason, :integer)
    field(:blocks, :binary)
    field(:extras, :binary)
  end

  @select ~w(id hash prev creator coinbase count tx_count size reason)a

  import Schema.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(x in Round, where: x == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> ""
      x -> map(x)
    end
  end

  def all(params) do
    from(Round)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> map()
  end

  defp filter_select(query) do
    select(query, [x], map(x, @select))
  end

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [x], asc: x.id)
  defp sort(query, _), do: order_by(query, [x], desc: x.id)

  defp map(map) do
    map
    |> Map.merge(%{hash: Base.encode16(map.hash), prev: Base.encode16(map.prev)})
  end
end
