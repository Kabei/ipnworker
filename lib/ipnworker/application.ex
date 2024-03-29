defmodule Ipnworker.Application do
  @moduledoc false
  use Application
  require Logger
  alias Ippan.{ClusterNodes, DetsSup}

  @app Mix.Project.config()[:app]

  @impl true
  def start(_type, _args) do
    load_env_file()
    check_branch()
    start_node()
    make_folders()
    load_keys()

    children =
      [
        MemTables,
        DetsSup,
        MainStore,
        LocalStore,
        PgStore,
        Ipnworker.Repo,
        :poolboy.child_spec(:minerpool, miner_config()),
        {Phoenix.PubSub, [name: :pubsub]},
        ClusterNodes
      ] ++
        http_service()

    opts = [strategy: :one_for_one, name: Ipnworker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp check_branch do
    try do
      {branch, 0} = System.cmd("git", ["branch", "--show-current"])
      :persistent_term.put(:branch, String.trim(branch))
    catch
      _ ->
        Logger.error("Git is not installed")
    end
  end

  defp start_node do
    vid =
      System.get_env("VID") || raise IppanStartUpError, "variable VID (ValidatorID) is missing"

    name = System.get_env("NAME") || raise IppanStartUpError, "variable NAME is missing"
    miner = System.get_env("MINER") || raise IppanStartUpError, "variable MINER is missing"

    :persistent_term.put(:vid, vid)
    :persistent_term.put(:name, name)
    :persistent_term.put(:miner, miner)
    :persistent_term.put(:status, :startup)
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

  defp http_service do
    config = Application.get_env(@app, :http)
    port = Keyword.get(config, :port, 0)

    case port do
      x when x > 0 ->
        [{Bandit, config}]

      _ ->
        []
    end
  end

  defp load_env_file do
    path = System.get_env("ENV_FILE", "env_file")

    if File.exists?(path) do
      File.stream!(path, [], :line)
      |> Enum.each(fn text ->
        text
        |> String.trim()
        |> String.replace(~r/\n|\r|#.+/, "")
        |> String.split("=", parts: 2)
        |> case do
          [key, value] ->
            System.put_env(key, value)

          _ ->
            :ignored
        end
      end)
    end
  end

  defp miner_config do
    [name: {:local, :minerpool}, worker_module: MinerWorker, size: 5, max_overflow: 2]
  end
end
