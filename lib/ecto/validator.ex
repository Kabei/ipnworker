defmodule Ippan.Ecto.Validator do
  alias Ippan.{Validator, Utils}
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Sqlite
  require Validator

  @table "validator"
  @select ~w(id hostname port name owner class pubkey net_pubkey image fa fb active failures env created_at updated_at)a

  def me do
    db_ref = :persistent_term.get(:main_ro)
    vid = :persistent_term.get(:vid)
    Validator.get(vid) |> fun()
  end

  def one(id) do
    db_ref = :persistent_term.get(:main_ro)

    case Match.hostname?(id) do
      false ->
        Validator.get(id)

      _ ->
        Validator.get_host(id)
    end
    |> fun()
  end

  def exists?(id) do
    db_ref = :persistent_term.get(:main_ro)
    Validator.exists?(id)
  end

  def exists_host?(hostname) do
    q =
      from(@table)
      |> where([v], v.hostname == ^hostname)
      |> select([v], v.id)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, []} -> false
      {:ok, _results} -> true
      _ -> false
    end
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_search(params)
      |> filter_class(params)
      |> filter_active(params)
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

  defp filter_class(query, %{"class" => class}) do
    q = "%#{class}%"

    where(query, [v], like(fragment("UPPER(?)", v.class), ^q))
  end

  defp filter_class(query, _), do: query

  defp filter_while(query, %{"last_updated" => time}) do
    where(query, [t], t.updated_at > ^time)
  end

  defp filter_while(query, _), do: query

  defp filter_active(query, %{"active" => "0"}) do
    where(query, [b], b.status == false)
  end

  defp filter_active(query, %{"active" => "1"}) do
    where(query, [b], b.status == true)
  end

  defp filter_active(query, _), do: query

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
