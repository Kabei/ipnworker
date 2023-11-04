defmodule Ipnworker.NodeSync do
  use GenServer
  alias Ippan.{Node, ClusterNodes}
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

  @offset 50
  @opts timeout: 10_000, retry: 10

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(local_round_id) do
    IO.inspect("nodeSync: init")
    miner = :persistent_term.get(:miner)
    db_ref = :persistent_term.get(:net_conn)
    node = Node.get(miner)

    if is_nil(node) do
      IO.inspect("no init")
      {:stop, :normal}
    else
      {:ok, {remote_round_id, _hash}} =
        ClusterNodes.call(node.id, "last_round", nil, @opts)

      diff = remote_round_id - local_round_id

      if diff > 0 do
        IO.inspect("init sync")
        init_round = max(local_round_id, 0)
        :ets.new(:sync, @ets_opts)
        :persistent_term.put(:node_sync, self())

        {:ok,
         %{
           db_ref: db_ref,
           node: node.id,
           hostname: node.hostname,
           offset: 0,
           queue: :ets.whereis(:sync),
           round: init_round,
           starts: local_round_id + 1,
           target: remote_round_id
         }, {:continue, :init}}
      else
        IO.inspect("No Sync")
        {:stop, :normal}
      end
    end
  end

  @impl true
  def handle_continue(
        :init,
        state = %{
          hostname: hostname,
          node: node_id,
          offset: offset,
          starts: starts,
          round: round_id,
          target: target_id,
          queue: ets_queue
        }
      ) do
    IO.inspect("round: ##{round_id}")

    {:ok, new_rounds} =
      ClusterNodes.call(node_id, "get_rounds", %{
        "limit" => @offset,
        "offset" => offset,
        "starts" => starts
      })

    Enum.each(new_rounds, fn new_round ->
      round = MapUtil.to_atoms(new_round)
      build(round, hostname)
    end)

    if round_id >= target_id do
      if :ets.info(ets_queue, :size) > 0 do
        {:noreply, state, {:continue, {:next, :ets.first(ets_queue)}}}
      else
        {:stop, :normal, state}
      end
    else
      {:noreply, %{state | offset: offset + @offset, round: round_id + @offset},
       {:continue, :init}}
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
    :ets.delete(ets_queue, key)

    {:noreply, state, {:continue, {:next, :ets.next(ets_queue, key)}}}
  end

  @impl true
  def terminate(_reason, %{queue: ets_queue}) do
    :persistent_term.erase(:node_sync)
    :ets.delete(ets_queue)
  end

  def terminate(_reason, _state), do: :ok

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
