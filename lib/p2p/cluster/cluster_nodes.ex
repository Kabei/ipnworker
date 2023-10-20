defmodule Ippan.ClusterNodes do
  alias Ippan.{Node, Network, BlockHandler, TxHandler, Round, Validator}
  require Sqlite
  require BalanceStore
  require Ippan.{Node, Validator, Round, TxHandler}

  @pubsub :pubsub
  @token Application.compile_env(:ipnworker, :token)

  use Network,
    app: :ipnworker,
    name: :cluster,
    table: :cnw,
    server: Ippan.ClusterNodes.Server,
    pubsub: :pubsub,
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
    db_ref = :persistent_term.get(:net_conn)
    default_port = Application.get_env(:ipnworker, :cluster)[:port]

    Node.delete_all()

    # register nodes from env_file Nodes argument
    String.split(nodes, ",", trim: true)
    |> Enum.reduce([], fn x, acc ->
      acc ++ [x |> String.trim() |> String.split("@", parts: 2)]
    end)
    |> Enum.each(fn [name_id, hostname] ->
      node =
        %Node{
          id: name_id,
          hostname: hostname,
          port: default_port,
          pubkey: pk,
          net_pubkey: net_pk
        }
        |> Node.to_list()

      Node.insert(node)
    end)

    Sqlite.sync(db_ref)
    next_init()
    connect_to_miner(db_ref)
  end

  defp next_init do
    db_ref = :persistent_term.get(:main_conn)
    vid = :persistent_term.get(:vid)
    v = Validator.get(vid)
    :persistent_term.put(:validator, v)
  end

  defp connect_to_miner(db_ref) do
    miner = :persistent_term.get(:miner)

    case Node.fetch(miner) do
      nil ->
        :ok

      node ->
        connect_async(Node.list_to_map(node))
    end
  end

  @impl Network
  def fetch(id) do
    db_ref = :persistent_term.get(:net_conn)
    Node.get(id)
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
    IO.inspect("handle 1")
    mow = :persistent_term.get(:mow)
    round = MapUtil.to_existing_atoms(msg_round)

    if mow do
      pgid = PgStore.pool()

      IO.inspect("handle 2")

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
    IO.inspect("step 0")
    db_ref = :persistent_term.get(:main_conn)
    writer = pg_conn != nil

    IO.inspect("step 0/5")

    unless Round.exists?(round_id) do
      vid = :persistent_term.get(:vid)
      balance_pid = DetsPlux.get(:balance)
      balance_tx = DetsPlux.tx(:balance)

      IO.inspect(round.id)

      pool_pid = Process.whereis(:minerpool)
      IO.inspect("step 1")
      is_some_block_mine = Enum.any?(round.blocks, fn x -> Map.get(x, "creator") == vid end)

      # blocks_len = length(blocks)

      # if blocks_len != 0 do
      #   next_block_id = :persistent_term.get(:block_id, 0) + blocks_len - 1
      #   :persistent_term.put(:block_id, next_block_id)
      # end

      for block = %{"creator" => block_creator_id} <- blocks do
        # if vid == block_creator_id do
        #   if :persistent_term.get(:height, 0) < height do
        #     :persistent_term.put(:height, height)
        #   end
        # end

        Task.async(fn ->
          creator = Validator.get(block_creator_id)

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

      TxHandler.run_deferred_txs()

      round_creator =
        Validator.get(round_creator_id)

      run_reward(round, round_creator, balance_pid, balance_tx)
      run_jackpot(round, db_ref, pg_conn)

      if reason > 0 do
        Validator.delete(round_creator_id)
      end

      IO.inspect("step 3")
      round_encode = Round.to_list(round)
      Round.insert(round_encode)

      # save balances
      run_save_balances(balance_tx, pg_conn)

      RoundCommit.sync(db_ref, tx_count, is_some_block_mine)
      IO.inspect("step 4")

      if writer do
        {:ok, _} = PgStore.insert_round(pg_conn, round_encode)
      end

      # Push event
      PubSub.broadcast(@pubsub, "round.new", round)
      PubSub.broadcast(@pubsub, "round:#{round_id}", round)

      # :persistent_term.put(:round, round_id)
    end
  end

  defp run_reward(%{reward: reward}, creator, balance_pid, balance_tx) when reward > 0 do
    balance_key = DetsPlux.tuple(creator.owner, @token)
    BalanceStore.income(balance_pid, balance_tx, balance_key, reward)
  end

  defp run_reward(_, _, _, _), do: :ok

  defp run_jackpot(%{id: round_id, jackpot: {amount, winner}}, db_ref, pgid)
       when amount > 0 do
    data = [round_id, winner, amount]
    :done = Sqlite.step("insert_jackpot", data)

    if pgid do
      PgStore.insert_jackpot(pgid, data)
    end

    # Push event
    PubSub.broadcast(@pubsub, "jackpot", %{
      "round_id" => round_id,
      "winner" => winner,
      "amount" => amount
    })
  end

  defp run_jackpot(_, _, _), do: :ok

  defp run_save_balances(_tx, nil), do: nil

  defp run_save_balances(balance_tx, pg_conn) do
    :ets.tab2list(balance_tx)
    |> Enum.each(fn {_, {key, {balance, lock}}} ->
      [id, token] = String.split(key, "|", parts: 2)
      PgStore.insert_balance(pg_conn, [id, token, balance, lock])
    end)
  end
end
