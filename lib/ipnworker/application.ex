defmodule Ipnworker.Application do
  @moduledoc false
  use Application
  alias Ippan.{ClusterNodes, DetsSup}

  @app Mix.Project.config()[:app]

  @impl true
  def start(_type, _args) do
    start_node()
    make_folders()
    load_keys()

    children = [
      MemTables,
      DetsSup,
      MainStore,
      NetStore,
      PgStore,
      Ipnworker.Repo,
      :poolboy.child_spec(:minerpool, miner_config()),
      {Phoenix.PubSub, [name: :pubsub]},
      ClusterNodes,
      {Bandit, Application.get_env(@app, :http)}
    ]

    opts = [strategy: :one_for_one, name: Ipnworker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_node do
    vid =
      System.get_env("VID") || raise IppanStartUpError, "variable VID (ValidatorID) is missing"

    name = System.get_env("NAME") || raise IppanStartUpError, "variable NAME is missing"
    miner = System.get_env("MINER") || raise IppanStartUpError, "variable MINER is missing"

    :persistent_term.put(:vid, :erlang.binary_to_integer(vid))
    :persistent_term.put(:name, name)
    :persistent_term.put(:miner, miner)
  end

  defp load_keys do
    seed_kem = System.get_env("CLUSTER_KEY") |> Fast64.decode64()
    seed = System.get_env("SECRET_KEY") |> Fast64.decode64()
    auth = System.get_env("AUTH") || raise RuntimeError, "variable AUTH is missing"

    {:ok, net_pubkey, net_privkey} = NtruKem.gen_key_pair_from_seed(seed_kem)
    {:ok, {pubkey, privkey}} = Cafezinho.Impl.keypair_from_seed(seed)

    :persistent_term.put(:pubkey, pubkey)
    :persistent_term.put(:privkey, privkey)
    :persistent_term.put(:net_pubkey, net_pubkey)
    :persistent_term.put(:net_privkey, net_privkey)
    :persistent_term.put(:auth, auth)
  end

  defp make_folders do
    # catch routes
    data_dir = System.get_env("data_dir", "data")
    block_dir = Path.join(data_dir, "blocks")
    decode_dir = Path.join(data_dir, "blocks/decoded")
    store_dir = Path.join(data_dir, "store")
    save_dir = Path.join(data_dir, "store/save")
    # set variables
    :persistent_term.put(:data_dir, data_dir)
    :persistent_term.put(:block_dir, block_dir)
    :persistent_term.put(:decode_dir, decode_dir)
    :persistent_term.put(:store_dir, store_dir)
    :persistent_term.put(:save_dir, save_dir)
    # make folders
    File.mkdir(data_dir)
    File.mkdir(store_dir)
    File.mkdir(block_dir)
    File.mkdir(decode_dir)
    File.mkdir(save_dir)
  end

  defp miner_config do
    [name: {:local, :minerpool}, worker_module: MinerWorker, size: 5, max_overflow: 2]
  end
end
