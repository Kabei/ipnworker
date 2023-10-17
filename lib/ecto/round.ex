defmodule Ippan.Ecto.Round do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "rounds" do
    field(:id, :integer)
    field(:hash, :binary)
    field(:prev, :binary)
    field(:creator, :integer)
    field(:signature, :binary)
    field(:coinbase, :integer)
    field(:reward, :integer)
    field(:count, :integer)
    field(:tx_count, :integer)
    field(:size, :integer)
    field(:reason, :integer)
    field(:blocks, :binary)
    field(:extras, :binary)
  end

  @select ~w(id hash prev creator coinbase reward count tx_count size reason)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(r in Round, where: r.id == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def last do
    from(r in Round, limit: 1, order_by: [desc: r.id])
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def all(params) do
    from(Round)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_select(query) do
    select(query, [r], map(r, @select))
  end

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [r], asc: r.id)
  defp sort(query, _), do: order_by(query, [r], desc: r.id)

  defp fun(x = %{hash: hash, prev: prev}) do
    %{x | hash: Utils.encode16(hash), prev: Utils.encode16(prev)}
  end
end
