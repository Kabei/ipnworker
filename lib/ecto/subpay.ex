defmodule Ippan.Ecto.SubPay do
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3, join: 5]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  @table "subpay"
  @table_service "serv"

  def one(id, payer, token) do
    db_ref = :persistent_term.get(:main_ro)

    SubPay.get(db_ref, id, payer, token)
  end

  def total(payer) do
    db_ref = :persistent_term.get(:main_ro)

    SubPay.total(db_ref, payer)
  end

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_join(params)
      |> filter_account(params)
      |> filter_search(params)
      |> filter_select(params)
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:main_ro)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &to_map(&1))

      _ ->
        []
    end
  end

  defp filter_select(query, %{"service" => _}) do
    select(query, [sp, s], %{
      id: sp.id,
      payer: sp.payer,
      token: sp.token,
      every: sp.every,
      extra: sp.extra,
      spent: sp.spent,
      status: sp.status,
      created_at: sp.created_at,
      lastPay: sp.lastPay,
      name: s.name,
      image: s.image
    })
  end

  defp filter_select(query, _) do
    select(
      query,
      [sp],
      map(sp, ~w(id payer token lastPay every spent extra created_at div)a)
    )
  end

  defp filter_search(query, %{"q" => q}) do
    q = String.upcase("%#{q}%")

    where(
      query,
      [sp],
      like(fragment("UPPER(?)", sp.id), ^q) or like(fragment("UPPER(?)", sp.name), ^q)
    )
  end

  defp filter_search(query, _), do: query

  defp filter_account(query, %{"id" => id}) do
    where(query, [sp], sp.id == ^id)
  end

  defp filter_account(query, %{"payer" => payer}) do
    where(query, [sp], sp.payer == ^payer)
  end

  defp filter_account(query, %{"id" => id, "payer" => payer}) do
    where(query, [sp], sp.id == ^id and sp.payer == ^payer)
  end

  defp filter_account(query, _), do: query

  def filter_join(query, %{"service" => _}) do
    join(query, :inner, [sp], s in @table_service, on: sp.id == s.id)
  end

  def filter_join(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [sp], asc: sp.created_at)
  defp sort(query, %{"sort" => "moreActive"}), do: order_by(query, [sp], desc: sp.last_round)
  defp sort(query, %{"sort" => "lessActive"}), do: order_by(query, [sp], asc: sp.last_round)
  defp sort(query, _), do: order_by(query, [sp], desc: sp.created_at)

  defp to_map([id, payer, token, lastPay, every, spent, extra, created_at, div]) do
    %{
      id: id,
      payer: payer,
      token: token,
      created_at: created_at,
      spent: spent,
      every: every,
      extra: Jason.decode!(extra),
      lastPay: lastPay,
      div: div
    }
  end

  defp to_map([id, payer, token, every, extra, spent, status, created_at, lastPay, name, image]) do
    %{
      id: id,
      payer: payer,
      token: token,
      name: name,
      image: image,
      spent: spent,
      every: every,
      status: status,
      created_at: created_at,
      extra: Jason.decode!(extra),
      lastPay: lastPay
    }
  end
end
