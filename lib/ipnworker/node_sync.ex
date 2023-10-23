defmodule Ipnworker.NodeSync do
  use GenServer
  alias Ippan.Round
  alias Ippan.Node
  alias Ippan.ClusterNodes
  require Ippan.{Node, Round}
  require Sqlite
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    miner = :persistent_term.get(:miner)
    db_ref = :persistent_term.get(:net_conn)
    {local_round_id, _hash} = Round.last({-1, nil})
    node = Node.get(miner)

    if is_nil(node) do
      {:stop, :normal, nil}
    else
      {:ok, {remote_round_id, _hash}} = ClusterNodes.call(node, "last_round")

      diff = remote_round_id - local_round_id

      if diff > 0 do
        {:ok, %{miner: node, round: local_round_id, target: remote_round_id}, {:continue, :init}}
      else
        {:stop, :normal, nil}
      end
    end
  end

  @impl true
  def handle_continue(:init, state = %{miner: node, round: round_id, target: target_id}) do
    {:ok, new_round} = ClusterNodes.call(node, "get_round")
    build(new_round, node.hostname)
    next_id = round_id + 1

    if next_id == target_id do
      {:stop, :normal, state}
    else
      {:noreply, %{state | round: next_id}, {:continue, :init}}
    end
  end

  def handle_continue(:init, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, nil) do
    Logger.debug("NodeSync: Nothing")
  end

  def terminate(_reason, %{target: target_id}) do
    Logger.debug("NodeSync: Success!! | #{target_id}")
  end

  defp build(new_round, hostname) do
    pgid = PgStore.pool()

    Postgrex.transaction(
      pgid,
      fn conn ->
        ClusterNodes.build_round(new_round, hostname, conn)
      end,
      timeout: :infinity
    )
  end
end
