defmodule Ippan.ClusterNode do
  alias Ippan.BlockHandler
  alias Ippan.Validator
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

    # register nodes from env_file Nodes argument
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
    init_db()
    # connect_to_miner()
  end

  defp init_db do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    vid = :persistent_term.get(:vid)
    :persistent_term.put(:dets_balance, Process.whereis(:balance))
    v = SqliteStore.lookup_map(:validator, conn, stmts, "get_validator", vid, Validator)
    :persistent_term.put(:validator, v)

    case SqliteStore.fetch(conn, stmts, "last_block_created") do
      nil ->
        :persistent_term.put(:height, 0)

      [_, _, height] ->
        :persistent_term.put(:height, height)
    end
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
  def handle_request("verify_block", data, _state) do
    BlockHandler.verify_file!(data)
  end

  def handle_request(_method, _data, _state), do: "not found"

  @impl Network
  def handle_message("validator.update", %{"id" => vid, "args" => args}, _state) do
    map = MapUtil.to_atoms(args)

    if :persistent_term.get(:vid) == vid do
      validator = :persistent_term.get(:validator)
      :persistent_term.put(:validator, Map.merge(validator, map))
    end
  end

  def handle_message("round.new", %{"id" => id, "blocks" => blocks}, _state) do
    vid = :persistent_term.get(:vid)
    :persistent_term.put(:round, id)

    Enum.each(blocks, fn %{"creator" => creator, "height" => height} ->
      if creator == vid do
        :persistent_term.put(:height, height)
      end
    end)
  end

  def handle_message(_event, _data, _state), do: :ok
end
