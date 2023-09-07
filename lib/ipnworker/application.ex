defmodule Ipnworker.Application do
  @moduledoc false

  use Application
  alias Ippan.ClusterNode

  @otp_app :ipnworker

  @impl true
  def start(_type, _args) do
    start_node()
    make_folders()
    load_keys()

    children = [
      {MemTables, []},
      {MainStore, []},
      {PgStore, [:init]},
      Supervisor.child_spec({Phoenix.PubSub, [name: :cluster]}, id: :cluster),
      ClusterNode,
      {Bandit, [plug: Ipnworker.Endpoint, scheme: :http] ++ Application.get_env(@otp_app, :http)}
    ]

    opts = [strategy: :one_for_one, name: Ipnworker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_node do
    miner = System.get_env("MINER")

    if is_nil(miner) do
      raise RuntimeError, "Set up a miner"
    end

    :persistent_term.put(:node, System.get_env("NODE"))
    :persistent_term.put(:vid, String.to_integer(System.get_env("VID", "0")))
    :persistent_term.put(:miner, System.get_env("MINER"))
  end

  defp load_keys do
    seed_kem = System.get_env("CLUSTER_KEY") |> Fast64.decode64()
    seed = System.get_env("SECRET_KEY") |> Fast64.decode64()

    {:ok, net_pubkey, net_privkey} = NtruKem.gen_key_pair_from_seed(seed_kem)
    {:ok, {pubkey, privkey}} = Cafezinho.Impl.keypair_from_seed(seed)

    :persistent_term.put(:pubkey, pubkey)
    :persistent_term.put(:privkey, privkey)
    :persistent_term.put(:net_pubkey, net_pubkey)
    :persistent_term.put(:net_privkey, net_privkey)
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
end
