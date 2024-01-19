defmodule Ippan.Ecto.Jackpot do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "jackpot" do
    field(:round_id, :integer)
    field(:winner, :binary)
    field(:amount, :integer)
  end

  @select ~w(round_id winner amount)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(j in Jackpot, where: j.round_id == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
  end

  def last do
    from(j in Jackpot, limit: 1, order_by: [desc: j.round_id])
    |> filter_select()
    |> Repo.one()
  end

  def all(params) do
    from(Jackpot)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_round(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
  end

  defp filter_select(query) do
    select(query, [j], map(j, @select))
  end

  defp filter_round(query, %{"end" => fin, "start" => start}) do
    where(query, [j], j.round_id >= ^start and j.round_id <= ^fin)
  end

  defp filter_round(query, %{"end" => id}) do
    where(query, [j], j.round_id <= ^id)
  end

  defp filter_round(query, %{"start" => id}) do
    where(query, [j], j.round_id >= ^id)
  end

  defp filter_round(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [j], asc: j.round_id)
  defp sort(query, _), do: order_by(query, [j], desc: j.round_id)
end
