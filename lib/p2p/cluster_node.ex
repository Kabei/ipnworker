defmodule Ippan.ClusterNode do
  alias Ippan.{LocalNode, Network}
  require SqliteStore

  use Network,
    app: :ipnworker,
    name: :cluster,
    table: :cnw,
    pubsub: :cluster,
    topic: "cluster",
    conn_opts: [reconnect: true, retry: :infinity],
    sup: Ippan.ClusterSup

  def on_init(_) do
    nodes = System.get_env("NODES")

    if is_nil(nodes) do
      IO.puts(IO.ANSI.red() <> "ERROR: variable NODES is missing" <> IO.ANSI.reset())
      System.halt(1)
    end

    pk = :persistent_term.get(:pubkey)
    net_pk = :persistent_term.get(:net_pubkey)
    net_conn = :persistent_term.get(:net_conn)
    net_stmts = :persistent_term.get(:net_stmt)
    default_port = Application.get_env(:ipnworker, :cluster)[:port]

    SqliteStore.step(net_conn, net_stmts, "delete_nodes", [])

    String.split(nodes, ",", trim: true)
    |> Enum.reduce([], fn x, acc ->
      acc ++ [x |> String.trim() |> String.split("@", parts: 2)]
    end)
    |> Enum.each(fn [name_id, hostname] ->
      data =
        %LocalNode{
          id: name_id,
          hostname: hostname,
          port: default_port,
          pubkey: pk,
          net_pubkey: net_pk
        }
        |> LocalNode.to_list()

      SqliteStore.step(net_conn, net_stmts, "insert_node", data)
    end)

    SqliteStore.sync(net_conn)

    connect_to_miner()
  end

  defp connect_to_miner do
    miner = :persistent_term.get(:miner)
    conn = :persistent_term.get(:net_conn)
    stmts = :persistent_term.get(:net_stmt)

    case SqliteStore.fetch(conn, stmts, "get_node", [miner]) do
      nil ->
        :ok

      node ->
        connect_async(LocalNode.list_to_map(node))
    end
  end

  @impl Network
  def fetch(id) do
    SqliteStore.lookup_map(
      :cluster,
      :persistent_term.get(:net_conn),
      :persistent_term.get(:net_stmt),
      "get_node",
      id,
      LocalNode
    )
  end

  @impl Network
  def handle_request(_method, _data, _state), do: "not found"

  @impl Network
  def handle_message(_event, _data, _state), do: :ok
end
