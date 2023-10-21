defmodule Ippan.Ecto.Block do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "blocks" do
    field(:id, :integer)
    field(:creator, :integer)
    field(:height, :integer)
    field(:hash, :binary)
    field(:prev, :binary)
    field(:hashfile, :binary)
    field(:signature, :binary)
    field(:round, :integer)
    field(:timestamp, :integer)
    field(:count, :integer)
    field(:rejected, :integer)
    field(:size, :integer)
    field(:vsn, :integer)
  end

  @select ~w(id creator height hash prev hashfile signature round timestamp count rejected size vsn)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(b in Block, where: b.id == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def last do
    from(b in Block, limit: 1, order_by: [desc: b.id])
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def all(params) do
    from(Block)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_below(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_select(query) do
    select(query, [b], map(b, @select))
  end

  defp filter_below(query, %{"below" => id}) do
    where(query, [b], b.id < ^id)
  end

  defp filter_below(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [b], asc: b.id)
  defp sort(query, _), do: order_by(query, [b], desc: b.id)

  defp fun(x = %{hash: hash, prev: prev, hashfile: hashfile, signature: signature}) do
    %{
      x
      | hash: Utils.encode16(hash),
        prev: Utils.encode16(prev),
        hashfile: Utils.encode16(hashfile),
        signature: Utils.encode64(signature)
    }
  end
end
