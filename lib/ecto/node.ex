defmodule Ippan.Ecto.Node do
  alias Ippan.{ClusterNodes, Node}
  alias Ipnworker.Repo
  import Ecto.Query, only: [from: 1, order_by: 3, select: 3, where: 3]
  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]
  require Node
  require Sqlite
  require Logger

  @table "node"
  @select ~w(id hostname port role pubkey net_pubkey avatar created_at)a

  def one(id) do
    db_ref = :persistent_term.get(:net_conn)

    Node.get(id)
  end

  def trigger("node.join", params) do
    timestamp = :erlang.system_time(:millisecond)

    result =
      params
      |> MapUtil.require(~w(id hostname port role))
      |> MapUtil.validate_hostname("hostname")
      |> MapUtil.validate_range("port", 1000..65535)
      |> MapUtil.validate_bytes_range("id", 0..255)
      |> MapUtil.validate_bytes_range("avatar", 0..255)
      |> MapUtil.transform("role", fn x ->
        String.split(x, " ", trim: true)
      end)
      |> Map.put(:created_at, timestamp)
      |> Map.put(:updated_at, timestamp)
      |> MapUtil.to_atoms()

    db_ref = :persistent_term.get(:net_conn)

    result
    |> Node.to_list()
    |> Node.insert()
    |> case do
      :done ->
        miner = :persistent_term.get(:miner)
        ClusterNodes.cast(miner, "node.join", result)
        :ok

      _ ->
        Logger.error("Node could not be recorded | #{inspect(result)}")
    end
  end

  def trigger("node.update", _params) do
    :ok
  end

  def trigger("node.leave", %{"id" => id}) do
    db_ref = :persistent_term.get(:net_conn)

    case Node.delete(id) do
      :done ->
        miner = :persistent_term.get(:miner)
        ClusterNodes.cast(miner, "node.leave", id)

      _ ->
        Logger.error("Node could not be deleted | #{inspect(id)}")
    end
  end

  def trigger(_, _), do: :undefined

  def all(params) do
    q =
      from(@table)
      |> filter_offset(params)
      |> filter_limit(params)
      |> filter_search(params)
      |> filter_select()
      |> sort(params)

    {sql, args} =
      Repo.to_sql(:all, q)

    db_ro = :persistent_term.get(:net_conn)

    case Sqlite.query(db_ro, sql, args) do
      {:ok, results} ->
        Enum.map(results, &Node.list_to_map(&1))

      _ ->
        []
    end
  end

  def total do
    db_ref = :persistent_term.get(:net_conn)
    Node.total()
  end

  defp filter_select(query) do
    select(query, [t], map(t, @select))
  end

  defp filter_search(query, %{"q" => q}) do
    q = "%#{q}%"
    where(query, [t], like(t.name, ^q))
  end

  defp filter_search(query, _), do: query

  defp sort(query, %{"sort" => "newest"}), do: order_by(query, [t], desc: t.created_at)
  defp sort(query, _), do: order_by(query, [t], asc: t.created_at)
end
