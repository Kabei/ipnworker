defmodule Ippan.ClusterNodes do
  alias Ippan.{Node, Network, BlockHandler}
  alias Ipnworker.NodeSync
  require Ippan.{Node}
  require Sqlite
  require BalanceStore

  @app Mix.Project.config()[:app]
  @pubsub :pubsub

  use Network,
    app: @app,
    name: :cluster,
    table: :cnw,
    server: Ippan.ClusterNodes.Server,
    pubsub: @pubsub,
    topic: "cluster",
    conn_opts: [reconnect: true, retry: :infinity],
    sup: Ippan.ClusterSup

  def on_init(_) do
    RoundBuilder.start_link()
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
      NodeSync.start_link()
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

  def handle_request(_method, _data, _state), do: {"error", "Not found"}

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
    GenServer.cast(RoundBuilder, {:build, round, hostname, true})
  end

  def handle_message("mempool", data, _state) do
    PubSub.broadcast(@pubsub, "mempool", data)
  end

  def handle_message(_event, _data, _state), do: :ok
end
