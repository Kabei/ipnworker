defmodule Ippan.ClusterNodes do
  alias Ippan.{Node, Network, BlockHandler, TxHandler, Round, Validator}
  alias Ipnworker.NodeSync
  require Ippan.{Node, Validator, Round, TxHandler}
  require Sqlite
  require BalanceStore

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @pubsub :pubsub
  @history Application.compile_env(@app, :history)
  @maintenance Application.compile_env(@app, :maintenance)

  use Network,
    app: @app,
    name: :cluster,
    table: :cnw,
    server: Ippan.ClusterNodes.Server,
    pubsub: :pubsub,
    topic: "cluster",
    conn_opts: [reconnect: true, retry: :infinity],
    sup: Ippan.ClusterSup

  def on_init(_) do
    connect_to_miner()
  end

  defp connect_to_miner do
    db_ref = :persistent_term.get(:main_conn)
    test = System.get_env("test")

    if is_nil(test) do
      IO.inspect("here go")

      miner = :persistent_term.get(:miner)

      case Node.fetch(miner) do
        nil ->
          :ok

        node_raw ->
          node = Node.list_to_map(node_raw)

          spawn_link(fn -> connect(node) end)
      end
    end
  end

  @impl Network
  def fetch(id) do
    db_ref = :persistent_term.get(:local_conn)
    Node.get(id)
  end

  @impl Network
  def exists?(id) do
    db_ref = :persistent_term.get(:local_conn)
    Node.exists?(id)
  end

  @impl Network
  def on_connect(
        node_id,
        %{
          socket: _socket,
          sharedkey: _sharedkey,
          hostname: _hostname,
          net_pubkey: _net_pubkey
        } =
          map
      ) do
    client_conn = Map.has_key?(map, :opts)
    Logger.debug("On connect #{node_id} opts: #{client_conn}")

    if client_conn do
      :ets.insert(@table, {node_id, map})
    else
      :ets.insert_new(@table, {node_id, map})
    end

    if node_id == :persistent_term.get(:miner) do
      spawn(fn ->
        NodeSync.start_link()
      end)
    end
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
  def handle_message("validator.update", %{"id" => _vid, "args" => _args}, _state) do
    # map = MapUtil.to_atoms(args)

    # if :persistent_term.get(:vid) == vid do
    #   validator = :persistent_term.get(:validator)
    #   Validator.self(Map.merge(validator, map))
    # end
    :ok
  end

  @doc """
  Create a new round. Received from a IPNCORE
  """
  def handle_message("round.new", msg_round, %{hostname: hostname} = _state) do
    # IO.inspect("handle 1")
    round = MapUtil.to_atoms(msg_round)

    unless node_syncing?(round) do
      if @history do
        pgid = PgStore.pool()

        # IO.inspect("handle 2")

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
  end

  def handle_message("mempool", data, _state) do
    PubSub.broadcast(@pubsub, "mempool", data)
  end

  def handle_message(_event, _data, _state), do: :ok

  def build_round(
        round = %{
          id: round_id,
          blocks: blocks,
          creator: round_creator_id,
          status: status,
          tx_count: tx_count
        },
        hostname,
        pg_conn
      ) do
    # IO.inspect("step 0")
    db_ref = :persistent_term.get(:main_conn)

    unless Round.exists?(round_id) do
      vid = :persistent_term.get(:vid)
      balance_pid = DetsPlux.get(:balance)
      balance_tx = DetsPlux.tx(:balance)
      # :persistent_term.put(:round, round_id)

      IO.puts("##{round.id}")

      pool_pid = Process.whereis(:minerpool)
      # IO.inspect("step 1")
      is_some_block_mine = Enum.any?(round.blocks, fn x -> Map.get(x, "creator") == vid end)

      for block = %{"creator" => block_creator_id} <- blocks do
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

      # IO.inspect("step 2")

      TxHandler.run_deferred_txs()

      round_creator =
        Validator.get(round_creator_id)

      run_reward(round, round_creator, balance_pid, balance_tx, pg_conn)
      run_jackpot(round, balance_pid, balance_tx, db_ref, pg_conn)

      if status > 0 do
        Validator.delete(round_creator_id)
        Sqlite.sync(db_ref)
      end

      # IO.inspect("step 3")
      round_encode = Round.to_list(round)
      Round.insert(round_encode)

      # Save balances
      run_save_balances(balance_tx, pg_conn)

      RegPay.commit(pg_conn, round_id)

      RoundCommit.sync(db_ref, tx_count, is_some_block_mine)
      # IO.inspect("step 4")

      if @history do
        PgStore.insert_round(pg_conn, round_encode)
        |> then(fn
          {:ok, _} ->
            :ok

          err ->
            IO.inspect(err)
        end)
      end

      # Push event
      msg = Round.to_text(round)
      PubSub.broadcast(@pubsub, "round.new", msg)
      PubSub.broadcast(@pubsub, "round:#{round_id}", msg)

      run_maintenance(round_id, db_ref)

      # :persistent_term.put(:round, round_id)

      fun = :persistent_term.get(:last_fun, nil)

      if fun do
        :persistent_term.erase(:last_fun)
        fun.()
      end
    end
  end

  defp run_reward(%{reward: amount}, %{owner: winner}, dets, tx, pg_conn) when amount > 0 do
    BalanceStore.income(dets, tx, winner, @token, amount)
    supply = TokenSupply.new(@token)
    TokenSupply.add(supply, amount)

    if pg_conn do
      RegPay.reward(winner, @token, amount)
    end
  end

  defp run_reward(_, _creator, _, _, _), do: :ok

  defp run_jackpot(
         %{id: round_id, jackpot: {winner, amount}},
         dets,
         tx,
         db_ref,
         pg_conn
       )
       when amount > 0 do
    data = [round_id, winner, amount]
    :done = Sqlite.step("insert_jackpot", data)
    BalanceStore.income(dets, tx, winner, @token, amount)
    supply = TokenSupply.jackpot()
    TokenSupply.put(supply, 0)

    if pg_conn do
      RegPay.jackpot(winner, @token, amount)
      PgStore.insert_jackpot(pg_conn, data)
    end

    # Push event
    PubSub.broadcast(@pubsub, "jackpot", %{
      "round_id" => round_id,
      "winner" => winner,
      "amount" => amount
    })
  end

  defp run_jackpot(_, _, _, _, _), do: :ok

  defp run_save_balances(_tx, nil), do: nil

  defp run_save_balances(balance_tx, pg_conn) do
    :ets.tab2list(balance_tx)
    |> Enum.each(fn {key, balance, lock} ->
      [id, token] = String.split(key, "|", parts: 2)
      PgStore.upsert_balance(pg_conn, [id, token, balance, lock])
    end)
  end

  defp run_maintenance(0, _), do: nil

  defp run_maintenance(round_id, db_ref) do
    if rem(round_id, @maintenance) == 0 do
      Sqlite.step("expiry_refund", [round_id])
      Sqlite.step("expiry_domain", [round_id])
    end
  end

  defp node_syncing?(round) do
    case :persistent_term.get(:node_sync, nil) do
      nil ->
        false

      pid ->
        case Process.alive?(pid) do
          true ->
            :ets.insert(:sync, {round.id, round})

          false ->
            :persistent_term.erase(:node_sync)
            false
        end
    end
  end
end
