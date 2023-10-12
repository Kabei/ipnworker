defmodule Ippan.ClusterNodes do
  alias Ippan.{LocalNode, Network, BlockHandler, TxHandler, Round, Validator}
  require SqliteStore
  require BalanceStore

  @pubsub :cluster
  @token Application.compile_env(:ipnworker, :token)

  use Network,
    app: :ipnworker,
    name: :cluster,
    table: :cnw,
    server: Ippan.ClusterNodes.Server,
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
  def handle_message("round.new", msg_round, %{hostname: hostname} = _state) do
    mow = :persistent_term.get(:mow)
    round = MapUtil.to_atoms(msg_round)

    if mow do
      pgid = PgStore.pool()

      Postgrex.transaction(
        pgid,
        fn conn ->
          build_round(round, hostname, conn)
        end,
        timeout: :infinity
      )
    else
      build_round(round, hostname, nil)
    end
  end

  def handle_message(_event, _data, _state), do: :ok

  defp build_round(
         round = %{
           id: round_id,
           blocks: blocks,
           creator: round_creator_id,
           reason: reason,
           tx_count: tx_count
         },
         hostname,
         pg_conn
       ) do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    writer = pg_conn != nil

    unless SqliteStore.exists?(conn, stmts, "exists_round", [round_id]) do
      vid = :persistent_term.get(:vid)
      balance_pid = DetsPlux.get(:balance)
      balance_tx = DetsPlux.tx(:balance)

      IO.inspect(round)

      pool_pid = Process.whereis(:minerpool)
      IO.inspect("step 1")
      is_some_block_mine = Enum.any?(round.blocks, fn x -> Map.get(x, "creator") == vid end)

      blocks_len = length(blocks)

      if blocks_len != 0 do
        next_block_id = :persistent_term.get(:block_id, 0) + blocks_len - 1
        :persistent_term.put(:block_id, next_block_id)
      end

      for block = %{"creator" => block_creator_id, "height" => height} <- blocks do
        if vid == block_creator_id do
          if :persistent_term.get(:height, 0) < height do
            :persistent_term.put(:height, height)
          end
        end

        Task.async(fn ->
          creator =
            SqliteStore.lookup_map(
              :validator,
              conn,
              stmts,
              "get_validator",
              block_creator_id,
              Validator
            )

          :poolboy.transaction(
            pool_pid,
            fn pid ->
              MinerWorker.mine(
                pid,
                round_id,
                MapUtil.to_atoms(block),
                hostname,
                creator,
                pg_conn
              )
            end,
            :infinity
          )
        end)
      end
      |> Task.await_many(:infinity)

      IO.inspect("step 2")
      wallets = {DetsPlux.get(:wallet), DetsPlux.tx(:wallet)}

      if writer do
        TxHandler.run_deferred_txs(conn, stmts, balance_pid, balance_tx, wallets, pg_conn)
      else
        TxHandler.run_deferred_txs(conn, stmts, balance_pid, balance_tx, wallets)
      end

      if reason > 0 do
        SqliteStore.step(conn, stmts, "delete_validator", [round_creator_id])
      end

      round_creator =
        SqliteStore.lookup_map(
          :validator,
          conn,
          stmts,
          "get_validator",
          round_creator_id,
          Validator
        )

      run_reward(round, round_creator, balance_pid, balance_tx)
      run_jackpot(round, conn, stmts, pg_conn)

      IO.inspect("step 3")
      round_encode = Round.to_list(round)
      SqliteStore.step(conn, stmts, "insert_round", round_encode)

      RoundCommit.sync(conn, tx_count, is_some_block_mine)

      if writer do
        {:ok, _} = PgStore.insert_round(pg_conn, round_encode)
      end

      :persistent_term.put(:round, round_id)
    end
  end

  defp run_reward(%{reward: reward}, creator, balance_pid, balance_tx) when reward > 0 do
    balance_key = DetsPlux.tuple(creator.owner, @token)
    BalanceStore.income(balance_pid, balance_tx, balance_key, reward)
  end

  defp run_reward(_, _, _, _), do: :ok

  defp run_jackpot(%{id: round_id, jackpot: {amount, winner_id}}, conn, stmts, pgid) do
    PubSub.broadcast(@pubsub, "jackpot", %{
      "round_id" => round_id,
      "winner" => winner_id,
      "amount" => amount
    })

    data = [round_id, winner_id, amount]
    :done = SqliteStore.step(conn, stmts, "insert_jackpot", data)

    if pgid do
      PgStore.insert_jackpot(pgid, data)
    end
  end

  defp run_jackpot(_, _, _round, _pgid), do: :ok
end
