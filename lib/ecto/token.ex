defmodule Ippan.Ecto.Token do
  alias Ippan.Token
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require Token

  @table "token"
  @select ~w(id name owner avatar decimal symbol max_supply props created_at updated_at)a

  def one(id) do
    db_ref = :persistent_term.get(:main_ro)

    Token.get(id)
    |> case do
      nil ->
        nil

      x ->
        dets = DetsPlux.get(:stats)
        amount = DetsPlux.get(dets, DetsPlux.tuple(id, "supply"), 0)
        Map.put(x, :supply, amount)
    end
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_select()
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &Token.list_to_map(&1))

      _ ->
        []
    end
  end

  defp filter_select(query) do
    select(query, [e], map(e, @select))
  end

  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [t], desc: t.created_at)
  defp sort(query, _), do: order_by(query, [t], asc: t.created_at)
end
