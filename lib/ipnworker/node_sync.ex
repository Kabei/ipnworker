defmodule Ipnworker.NodeSync do
  use GenServer
  alias Ippan.Round
  alias Ippan.Node
  alias Ippan.ClusterNodes
  require Ippan.{Node, Round}
  require Sqlite
  require Logger

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
        IO.inspect("init")
        init_round = max(local_round_id, 0)

        {:ok, %{db_ref: db_ref, miner: node, round: init_round, target: remote_round_id},
         {:continue, :init}}
      else
        IO.inspect("fail")
        {:stop, :normal, nil}
      end
    end
  end

  @impl true
  def handle_continue(
        :init,
        state = %{db_ref: db_ref, miner: node, round: round_id, target: target_id}
      ) do
    IO.inspect("round: ##{round_id}")
    {:ok, new_round} = ClusterNodes.call(node.id, "get_round", round_id)

    IO.inspect(new_round)

    build(new_round, node.hostname)

    if round_id == target_id do
      Sqlite.sync(db_ref)
      {:stop, :normal, state}
    else
      {:noreply, %{state | round: round_id + 1}, {:continue, :init}}
    end
  end

  def handle_continue(:init, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, nil) do
    Logger.debug("NodeSync: Nothing")
  end

  def terminate(_reason, %{round: round_id, target: target_id}) do
    Logger.debug("[NodeSync] | Success: #{target_id == round_id}")
  end

  defp build(new_round, hostname) do
    round = MapUtil.to_atoms(new_round)
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
