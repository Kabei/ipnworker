defmodule Ippan.Ecto.Round do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"

  schema "rounds" do
    field(:id, :decimal)
    field(:hash, :binary)
    field(:prev, :binary)
    field(:creator, :string)
    field(:signature, :binary)
    field(:reward, :decimal)
    field(:count, :integer)
    field(:tx_count, :integer)
    field(:size, :integer)
    field(:status, :integer)
    field(:timestamp, :integer)
    field(:blocks, :binary)
    field(:extra, :binary)
  end

  @select ~w(id hash prev creator signature reward count tx_count size status timestamp)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(id) do
    from(r in Round, where: r.id == ^id, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def last do
    from(r in Round, limit: 1, order_by: [desc: r.id])
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def all(params) do
    from(Round)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_range(params)
    |> filter_search(params)
    |> filter_status(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_search(query, %{"q" => q}) when byte_size(q) == 64 do
    where(query, [r], r.hash == ^Base.decode16!(q, case: :mixed))
  end

  defp filter_search(query, %{"q" => q}) do
    where(query, [r], r.id == ^Utils.check_integer(q, -1))
  end

  defp filter_search(query, _), do: query

  defp filter_select(query) do
    select(query, [r], map(r, @select))
  end

  defp filter_range(query, %{"end" => id}) do
    where(query, [r], r.id <= ^id)
  end

  defp filter_range(query, %{"start" => id}) do
    where(query, [r], r.id >= ^id)
  end

  defp filter_range(query, %{"end" => fin, "start" => start}) do
    where(query, [r], r.id >= ^start and r.id <= ^fin)
  end

  defp filter_range(query, %{"dateEnd" => fin, "dateStart" => start}) do
    start = Utils.date_start_to_time(start)
    fin = Utils.date_end_to_time(fin)

    where(query, [r], r.timestamp >= ^start and r.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateEnd" => fin}) do
    fin = Utils.date_end_to_time(fin)

    where(query, [r], r.timestamp <= ^fin)
  end

  defp filter_range(query, %{"dateStart" => start}) do
    start = Utils.date_end_to_time(start)

    where(query, [r], r.timestamp >= ^start)
  end

  defp filter_range(query, _), do: query

  defp filter_status(query, %{"status" => status}) do
    where(query, [r], r.status == ^status)
  end

  defp filter_status(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [r], asc: r.id)
  defp sort(query, _), do: order_by(query, [r], desc: r.id)

  defp fun(x = %{hash: hash, prev: prev, signature: signature}) do
    %{
      x
      | hash: Utils.encode16(hash),
        prev: Utils.encode16(prev),
        signature: Utils.encode64(signature)
    }
  end
end
