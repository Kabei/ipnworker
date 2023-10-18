defmodule Ippan.Ecto.DNS do
  alias Ippan.{DNS, Utils}
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require DNS

  @table "dns"
  @select ~w(domain hash name type data ttl)a

  def one(domain, hash16) do
    db_ref = :persistent_term.get(:main_ro)
    hash = Base.decode16(hash16, case: :mixed)

    DNS.get(domain, hash)
    |> tap(&IO.inspect(&1))
    |> fun()
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_type(params)
      |> filter_search(params)
      |> filter_select()
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &(DNS.list_to_map(&1) |> fun()))

      _ ->
        []
    end
  end

  defp filter_select(query) do
    select(query, [t], map(t, @select))
  end

  defp filter_search(query, %{"q" => q}) do
    q = "%#{q}%"
    where(query, [t], like(t.name, ^q))
  end

  defp filter_search(query, _), do: query

  defp filter_type(query, %{"type" => type}) do
    where(query, [t], like(t.type, ^type))
  end

  defp filter_type(query, _), do: query
  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [t], desc: t.created_at)
  defp sort(query, _), do: order_by(query, [t], asc: t.created_at)

  defp fun(nil), do: nil

  defp fun(x = %{hash: hash}) do
    %{x | hash: Utils.encode16(hash)}
  end
end
