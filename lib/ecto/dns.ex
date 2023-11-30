defmodule Ippan.Ecto.DNS do
  alias Ippan.{DNS, Utils}
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 2, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require DNS

  @table "dns"
  @select ~w(domain name type data ttl hash)a

  def one(domain, hash16) do
    db_ref = :persistent_term.get(:main_ro)
    hash = Base.decode16!(hash16, case: :mixed)

    case DNS.get(domain, hash) do
      nil ->
        nil

      dns ->
        DNS.list_to_map(dns)
        |> fun()
    end
  end

  def all(domain, params) do
    q =
      from(d in @table, where: d.domain == ^domain)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_where(params)
      |> filter_search(params)
      |> filter_select()

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
    where(query, [x], ilike(x.name, ^q))
  end

  defp filter_search(query, _), do: query

  defp filter_where(query, %{"name" => name, "type" => type}) do
    where(query, [x], x.name == ^name and x.type == ^type)
  end

  defp filter_where(query, %{"name" => name}) do
    where(query, [x], x.name == ^name)
  end

  defp filter_where(query, %{"type" => type}) do
    where(query, [x], x.type == ^type)
  end

  defp filter_where(query, _), do: query

  defp fun(x = %{hash: hash}) do
    %{x | hash: Utils.encode16(hash)}
  end
end
