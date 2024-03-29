defmodule Ippan.Ecto.Domain do
  alias Ippan.Domain
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require Domain

  @table "domain"
  @select ~w(name owner email image records created_at renewed_at updated_at)a

  def one(name) do
    db_ref = :persistent_term.get(:main_ro)

    Domain.get(name)
    |> Domain.list_to_map()
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_search(params)
      |> filter_while(params)
      |> filter_select()
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &Domain.list_to_map(&1))

      _ ->
        []
    end
  end

  defp filter_select(query) do
    select(query, [t], map(t, @select))
  end

  defp filter_search(query, %{"q" => q}) do
    where(query, [t], like(fragment("UPPER(?)", t.name), ^String.upcase("%#{q}%")))
  end

  defp filter_search(query, %{"owner" => owner}) do
    where(query, [t], t.owner == ^owner)
  end

  defp filter_search(query, %{"email" => email}) do
    where(query, [t], t.email == ^email)
  end

  defp filter_search(query, _), do: query

  defp filter_while(query, %{"last_updated" => time}) do
    where(query, [t], t.updated_at > ^time)
  end

  defp filter_while(query, _), do: query

  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [t], desc: t.created_at)
  defp sort(query, _), do: order_by(query, [t], asc: t.created_at)
end
