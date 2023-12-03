defmodule Ippan.Ecto.Validator do
  alias Ippan.{Validator, Utils}
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require Validator

  @table "validator"
  @select ~w(id hostname port name owner pubkey net_pubkey avatar fa fb stake failures created_at updated_at)a

  def me do
    :persistent_term.get(:validator) |> fun()
  end

  def one(id) do
    db_ref = :persistent_term.get(:main_ro)

    Validator.get(id)
    |> fun()
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
        Enum.map(results, &(Validator.list_to_map(&1) |> fun()))

      _ ->
        []
    end
  end

  defp filter_select(query) do
    select(query, [t], map(t, @select))
  end

  defp filter_search(query, %{"q" => q}) do
    q = String.upcase("%#{q}%")

    where(
      query,
      [t],
      like(fragment("UPPER(?)", t.name), ^q) or like(fragment("UPPER(?)", t.hostname), ^q)
    )
  end

  defp filter_search(query, _), do: query

  defp filter_while(query, %{"last_updated" => time}) do
    where(query, [t], t.updated_at > ^time)
  end

  defp filter_while(query, _), do: query

  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [t], desc: t.created_at)
  defp sort(query, _), do: order_by(query, [t], asc: t.created_at)

  defp fun(nil), do: nil

  defp fun(x = %{pubkey: pk, net_pubkey: npk}) do
    %{
      x
      | pubkey: Utils.encode64(pk),
        net_pubkey: Utils.encode64(npk)
    }
  end
end
