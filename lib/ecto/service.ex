defmodule Ippan.Ecto.Service do
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite

  @table "serv"
  @select ~w(id name owner image descrip subs extra status created_at updated_at)a

  def one(id) do
    db_ref = :persistent_term.get(:main_ro)

    PayService.get(db_ref, id)
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_search(params)
      |> filter_owner(params)
      |> filter_while(params)
      |> filter_select()
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &PayService.to_map(&1))

      _ ->
        []
    end
  end

  defp filter_select(query) do
    select(query, [s], map(s, @select))
  end

  defp filter_search(query, %{"q" => q}) do
    q = String.upcase("%#{q}%")

    where(
      query,
      [s],
      like(fragment("UPPER(?)", s.id), ^q) or like(fragment("UPPER(?)", s.name), ^q)
    )
  end

  defp filter_search(query, _), do: query

  defp filter_owner(query, %{"owner" => owner}) do
    where(query, [s], s.owner == ^owner)
  end

  defp filter_owner(query, _), do: query

  defp filter_while(query, %{"last_updated" => time}) do
    where(query, [s], s.updated_at > ^time)
  end

  defp filter_while(query, _), do: query

  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [s], desc: s.created_at)
  defp sort(query, _), do: order_by(query, [s], asc: s.created_at)
end
