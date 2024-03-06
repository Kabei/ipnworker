defmodule RoundBuilder do
  use GenServer
  alias Ippan.{TxHandler, Round, Validator}
  alias Phoenix.PubSub
  alias Ipnworker.NodeSync
  require Ippan.{Validator, Round, TxHandler}
  require Sqlite
  require BalanceStore
  require Logger

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @pubsub :pubsub
  @history Application.compile_env(@app, :history, false)
  @maintenance Application.compile_env(@app, :maintenance)

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    {:ok, nil}
  end

  @impl true
  def handle_cast({:build, round, hostname, check_sync}, state) do
    prepare_build(round, hostname, check_sync)

    {:noreply, state}
  end

  @impl true
  def handle_call({:build, round, hostname, check_sync}, _from, state) do
    prepare_build(round, hostname, check_sync)
    {:reply, :ok, state}
  end

  @spec prepare_build(round :: map, hostname :: String.t(), check_sync :: boolean()) :: any()
  if @history do
    defp prepare_build(round, hostname, false) do
      pgid = PgStore.pool()

      Postgrex.transaction(
        pgid,
        fn conn ->
          build_round(round, hostname, conn)
        end,
        timeout: :infinity
      )
    end

    defp prepare_build(round, hostname, true) do
      unless node_syncing?(round) do
        pgid = PgStore.pool()

        Postgrex.transaction(
          pgid,
          fn conn ->
            build_round(round, hostname, conn)
          end,
          timeout: :infinity
        )
      end
    end
  else
    defp prepare_build(round, hostname, true) do
      unless node_syncing?(round) do
        build_round(round, hostname, nil)
      end
    end

    defp prepare_build(round, hostname, false) do
      build_round(round, hostname, nil)
    end
  end

  defp build_round(
         round = %{
           id: round_id,
           hash: hash,
           blocks: blocks,
           creator: round_creator_id,
           count: block_count,
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
      balance_tx = DetsPlux.tx(balance_pid, :balance)
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

      case status do
        1 ->
          max = EnvStore.max_failures()

          if max != 0 do
            number = Validator.incr_failure(round_creator, 1, round_id)
            if number != nil and rem(number, max) == 0 do
              Validator.disable(round_creator, round_id)
            end

            Sqlite.sync(db_ref)
          end

        2 ->
          Validator.delete(round_creator_id)
          Sqlite.sync(db_ref)

        _ ->
          nil
      end

      # IO.inspect("step 3")
      round_encode = Round.to_list(round)
      Round.insert(round_encode)

      # Save balances
      run_save_balances(balance_tx, pg_conn)

      # update stats
      stats = Stats.new()
      Stats.incr(stats, "blocks", block_count)
      Stats.incr(stats, "txs", tx_count)
      Stats.put(stats, "last_round", round_id)
      Stats.put(stats, "last_hash", hash)

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
            NodeSync.add_queue(round)

          false ->
            :persistent_term.erase(:node_sync)
            false
        end
    end
  end
end
