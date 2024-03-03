defmodule Ipnworker.NodeSync do
  use GenServer, restart: :trasient
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

  @offset 200
  @opts timeout: 10_000, retry: 10

  def start_link do
    case Process.whereis(__MODULE__) do
      nil ->
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)

      pid ->
        {:already_stated, pid}
    end
  end

  @impl true
  def init(_args) do
    {:ok, nil, {:continue, :prepare}}
  end

  @impl true
  def handle_continue(:prepare, state) do
    miner = :persistent_term.get(:miner)
    db_ref = :persistent_term.get(:local_conn)
    node = Node.get(miner)
    builder_pid = Process.whereis(RoundBuilder)
    stats = Stats.cache()
    local_round_id = Stats.rounds(stats, -1)

    if is_nil(node) do
      IO.puts("NodeSync no init")
      {:stop, :normal, state}
    else
      {:ok, {remote_round_id, _hash}} =
        ClusterNodes.call(node.id, "last_round", nil, @opts)

      diff = remote_round_id - local_round_id

      if diff > 0 do
        init_round = max(local_round_id, 0)
        IO.puts("NodeSync starts from ##{init_round} to #{remote_round_id}")
        :persistent_term.put(:status, :sync)
        :persistent_term.put(:node_sync, self())
        :ets.new(:sync, @ets_opts)

        {:noreply,
         %{
           builder: builder_pid,
           db_ref: db_ref,
           node: node.id,
           hostname: node.hostname,
           offset: 0,
           queue: :ets.whereis(:sync),
           round: init_round,
           starts: local_round_id + 1,
           target: remote_round_id
         }, {:continue, :fetch}}
      else
        IO.inspect("No Sync")
        {:stop, :normal, state}
      end
    end
  end

  def handle_continue(
        :fetch,
        state = %{
          builder: builder_pid,
          hostname: hostname,
          node: node_id,
          offset: offset,
          starts: starts,
          round: round_id,
          target: target_id,
          queue: ets_queue
        }
      ) do
    if round_id < target_id do
      {:ok, new_rounds} =
        ClusterNodes.call(node_id, "get_rounds", %{
          "limit" => @offset,
          "offset" => offset,
          "starts" => starts
        })

      Enum.each(new_rounds, fn new_round ->
        round = MapUtil.to_atoms(new_round)
        build(builder_pid, round, hostname)
      end)

      len = length(new_rounds)

      {
        :noreply,
        %{state | offset: offset + len, round: round_id + len},
        {:continue, :fetch}
      }
    else
      if :ets.info(ets_queue, :size) > 0 do
        {:noreply, state, {:continue, {:next, :ets.first(ets_queue)}}}
      else
        {:stop, :normal, state}
      end
    end
  end

  def handle_continue({:next, :"$end_of_table"}, state) do
    {:stop, :normal, state}
  end

  def handle_continue(
        {:next, key},
        state = %{builder: builder_pid, hostname: hostname, queue: ets_queue}
      ) do
    IO.inspect("Queue | round: ##{key}")
    [{_key, round}] = :ets.lookup(ets_queue, key)
    build(builder_pid, round, hostname)
    :ets.delete(ets_queue, key)

    {:noreply, state, {:continue, {:next, :ets.next(ets_queue, key)}}}
  end

  @impl true
  def terminate(_reason, %{queue: ets_queue}) do
    :persistent_term.put(:status, :synced)
    :persistent_term.erase(:node_sync)
    :ets.delete(ets_queue)
  end

  def terminate(_reason, _state) do
    :persistent_term.put(:status, :synced)
    :persistent_term.erase(:node_sync)
    :ets.delete(ets_queue)
  end

  def add_queue(round) do
    :ets.insert(:sync, {round.id, round})
  end

  defp build(pid, round, hostname) do
    GenServer.call(pid, {:build, round, hostname, false}, :infinity)
  end
end
