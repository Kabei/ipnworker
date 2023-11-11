defmodule Ippan.Ecto.Balance do
  use Ecto.Schema
  import Ecto.Query, only: [from: 2, order_by: 3, select: 3]
  alias Ipnworker.Repo
  alias Ippan.Token
  require Ippan.Token
  require Sqlite
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "balance" do
    field(:id, :string)
    field(:token, :string)
    field(:balance, :integer)
    field(:lock, :integer)
  end

  @select ~w(token balance lock)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def all(params, id) do
    db_ref = :persistent_term.get(:main_conn)

    from(b in Balance, where: b.id == ^id)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(fn x ->
      token = Token.get(x.token)
      map = Map.take(token, ~w(avatar decimal max_supply symbol)a)
      Map.merge(x, map)
    end)
  end

  defp filter_select(query) do
    select(query, [x], map(x, @select))
  end

  defp sort(query, %{"sort" => "most_value"}), do: order_by(query, [x], desc: x.balance)
  defp sort(query, _), do: order_by(query, [x], desc: x.balance)
end
