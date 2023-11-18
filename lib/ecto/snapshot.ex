defmodule Ippan.Ecto.Snapshot do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "snapshot" do
    field(:round_id, :integer)
    field(:hash, :binary)
    field(:size, :integer)
  end

  @select ~w(round_id hash size)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(s in Snapshot, where: s.round_id == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def all(params) do
    from(Snapshot)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_range(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_select(query) do
    select(query, [s], map(s, @select))
  end

  defp filter_range(query, %{"end" => fin, "start" => start}) do
    where(query, [s], s.round_id >= ^start and s.round_id <= ^fin)
  end

  defp filter_range(query, %{"end" => id}) do
    where(query, [s], s.round_id <= ^id)
  end

  defp filter_range(query, %{"start" => id}) do
    where(query, [s], s.round_id >= ^id)
  end

  defp filter_range(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [s], asc: s.round_id)
  defp sort(query, _), do: order_by(query, [s], desc: s.round_id)

  defp fun(x = %{hash: hash}) do
    %{x | hash: Utils.encode16(hash)}
  end
end
