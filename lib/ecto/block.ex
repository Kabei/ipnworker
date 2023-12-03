defmodule Ippan.Ecto.Block do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "blocks" do
    field(:id, :string)
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
    field(:status, :integer)
    field(:vsn, :integer)
  end

  @select ~w(id creator height hash prev hashfile signature round timestamp count rejected size status vsn)a

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
    |> filter_round(params)
    |> filter_search(params)
    |> filter_range(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_search(query, %{"q" => q}) when byte_size(q) == 64 do
    where(query, [b], b.hash == ^Base.decode16!(q, case: :mixed))
  end

  defp filter_search(query, %{"q" => q}) do
    where(query, [b], b.id == ^Utils.check_integer(q, -1))
  end

  defp filter_search(query, _), do: query

  defp filter_select(query) do
    select(query, [b], map(b, @select))
  end

  defp filter_round(query, %{"round" => round_id}) do
    where(query, [b], b.round == ^round_id)
  end

  defp filter_round(query, _), do: query

  defp filter_range(query, %{"end" => fin, "start" => start}) do
    where(query, [b], b.id >= ^start and b.id <= ^fin)
  end

  defp filter_range(query, %{"end" => id}) do
    where(query, [b], b.id <= ^id)
  end

  defp filter_range(query, %{"start" => id}) do
    where(query, [b], b.id >= ^id)
  end

  defp filter_range(query, %{"dateEnd" => fin, "dateStart" => start}) do
    start = Utils.date_start_to_time(start)
    fin = Utils.date_end_to_time(fin)

    where(query, [b], b.timestamp >= ^start and b.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateEnd" => fin}) do
    fin = Utils.date_end_to_time(fin)

    where(query, [b], b.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateStart" => start}) do
    start = Utils.date_end_to_time(start)

    where(query, [b], b.timestamp >= ^start)
  end

  defp filter_range(query, _), do: query

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
