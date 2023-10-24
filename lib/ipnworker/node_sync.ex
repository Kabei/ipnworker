defmodule Ipnworker.NodeSync do
  use GenServer
  alias Ippan.Round
  alias Ippan.Node
  alias Ippan.ClusterNodes
  require Ippan.{Node, Round}
  require Sqlite
  require Logger

  @ets_opts [
    :ordered_set,
    :named_table,
    :public,
    read_concurrency: true,
    write_concurrency: true
  ]

  @opts timeout: 10_000, retry: 10

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    IO.inspect("nodeSync: init")
    miner = :persistent_term.get(:miner)
    db_ref = :persistent_term.get(:net_conn)
    {local_round_id, _hash} = Round.last({-1, nil})
    node = Node.get(miner)

    if is_nil(node) do
      IO.inspect("no init")
      {:stop, :normal, nil}
    else
      {:ok, {remote_round_id, _hash}} =
        ClusterNodes.call(node.id, "last_round", nil, @opts)

      diff = remote_round_id - local_round_id

      if diff > 0 do
        IO.inspect("init sync")
        init_round = max(local_round_id, 0)
        :ets.new(:queue, @ets_opts)
        :persistent_term.put(:node_sync, self())

        {:ok,
         %{
           db_ref: db_ref,
           node: node.id,
           hostname: node.hostname,
           queue: :ets.whereis(:queue),
           round: init_round,
           target: remote_round_id
         }, {:continue, :init}}
      else
        IO.inspect("No Sync")
        {:stop, :normal, nil}
      end
    end
  end

  @impl true
  def handle_continue(
        :init,
        state = %{
          hostname: hostname,
          node: node_id,
          round: round_id,
          target: target_id,
          queue: ets_queue
        }
      ) do
    IO.inspect("round: ##{round_id}")
    {:ok, new_round} = ClusterNodes.call(node_id, "get_round", round_id)
    round = MapUtil.to_atoms(new_round)

    build(round, hostname)

    if round_id == target_id do
      if :ets.info(ets_queue, :size) > 0 do
        {:noreply, state, {:continue, {:next, :ets.first(ets_queue)}}}
      else
        {:stop, :normal, state}
      end
    else
      {:noreply, %{state | round: round_id + 1}, {:continue, :init}}
    end
  end

  def handle_continue(:init, state) do
    {:stop, :normal, state}
  end

  def handle_continue({:next, :"$end_of_table"}, state) do
    {:stop, :normal, state}
  end

  def handle_continue({:next, key}, state = %{hostname: hostname, queue: ets_queue}) do
    IO.inspect("Queue | round: ##{key}")
    [{_key, round}] = :ets.lookup(ets_queue, key)
    build(round, hostname)
    :ets.delete(key)

    {:noreply, state, {:continue, {:next, :ets.next(ets_queue, key)}}}
  end

  @impl true
  def handle_cast({:round, round = %{id: id}}, state = %{queue: ets_queue}) do
    :ets.insert(ets_queue, {id, round})
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :persistent_term.erase(:node_sync)
  end

  defp build(round, hostname) do
    pgid = PgStore.pool()

    Postgrex.transaction(
      pgid,
      fn conn ->
        ClusterNodes.build_round(round, hostname, conn)
      end,
      timeout: :infinity
    )
  end
end
