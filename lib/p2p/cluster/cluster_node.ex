defmodule Ippan.ClusterNode do
  alias Ippan.{LocalNode, Network, BlockHandler, TxHandler, Round, Validator}
  require SqliteStore

  @pubsub :cluster

  use Network,
    app: :ipnworker,
    name: :cluster,
    table: :cnw,
    server: Ippan.ClusterNode.Server,
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
    init()
    connect_to_miner()
  end

  defp init do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    vid = :persistent_term.get(:vid)
    :persistent_term.put(:dets_balance, Process.whereis(:balance))
    v = SqliteStore.lookup_map(:validator, conn, stmts, "get_validator", vid, Validator)
    :persistent_term.put(:validator, v)

    case SqliteStore.fetch(conn, stmts, "last_block_created", []) do
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
    case BlockHandler.verify_file!(data) do
      :ok ->
        true

      :error ->
        false
    end
  end

  def handle_request(_method, _data, _state), do: ["error", "Not found"]

  @impl Network
  def handle_message("validator.update", %{"id" => vid, "args" => args}, _state) do
    map = MapUtil.to_atoms(args)

    if :persistent_term.get(:vid) == vid do
      validator = :persistent_term.get(:validator)
      :persistent_term.put(:validator, Map.merge(validator, map))
    end
  end

  @doc """
  Create a new round. Received from a IPNCORE
  """
  def handle_message("round.new", round = %{"id" => round_id, "blocks" => blocks}, state) do
    vid = :persistent_term.get(:vid)
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    dets = :persistent_term.get(:balance_dets)
    pg_conn = PgStore.conn()

    unless SqliteStore.exists?(conn, stmts, "exists_round", [round_id]) do
      PgStore.begin(conn)

      for block = %{"id" => block_id, "creator" => creator_id, "height" => height} <- blocks do
        if vid == creator_id do
          if :persistent_term.get(:height, 0) < height do
            :persistent_term.put(:height, height)
          end
        end

        if :persistent_term.get(:block_id, 0) < block_id do
          :persistent_term.put(:block_id, block_id)
        end

        Task.async(fn ->
          creator =
            SqliteStore.lookup_map(
              :validator,
              conn,
              stmts,
              "get_validator",
              creator_id,
              Validator
            )

          :poolboy.transaction(
            :minerpool,
            fn pid ->
              MinerWorker.create(pid, MapUtil.to_atoms(block), state.hostname, creator, round_id)
            end,
            :infinity
          )
        end)
      end
      |> Enum.map(fn t -> Task.await(t, :infinity) end)

      TxHandler.run_deferred_txs(conn, stmts, dets, pg_conn)

      r = Round.to_list(MapUtil.to_atoms(round))
      SqliteStore.step(conn, stmts, "insert_round", r)
      PgStore.insert_round(pg_conn, r)
      PgStore.commit(pg_conn)

      :persistent_term.put(:round, round_id)
    end
  end

  def handle_message("jackpot", [round_id, winner_id, amount] = data, _state) do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmts)

    PubSub.broadcast(@pubsub, "jackpot", %{
      "round_id" => round_id,
      "winner" => winner_id,
      "amount" => amount
    })

    SqliteStore.step(conn, stmts, "insert_jackpot", data)
  end

  def handle_message(_event, _data, _state), do: :ok
end
