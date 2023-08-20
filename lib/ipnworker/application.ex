defmodule Ipnworker.Application do
  @moduledoc false

  use Application
  # import Ippan.Utils, only: [to_atom: 1]

  @otp_app :ipnworker

  @impl true
  def start(_type, _args) do
    # miner = System.get_env("MINER") |> to_atom()

    make_folders()

    # case miner do
    #   nil -> raise IppanStartUpError, "Set up a miner"
    #   _ -> :ok
    # end

    children = [
      # {MemTables, []},
      Supervisor.child_spec({Phoenix.PubSub, [name: :workers]}, id: :workers),
      Supervisor.child_spec({Phoenix.PubSub, [name: :cores]}, id: :cores),
      {AssetStore, :persistent_term.get(:store_dir)},
      # {MinerClient, [miner]},
      # {NodeMonitor, miner},
      {Bandit, [plug: Ipnworker.Endpoint, scheme: :http] ++ Application.get_env(@otp_app, :http)}
    ]

    opts = [strategy: :one_for_one, name: Ipnworker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp make_folders do
    # catch routes
    data_dir = System.get_env("data_dir", "data")
    block_dir = Path.join(data_dir, "blocks")
    decode_dir = Path.join(data_dir, "blocks/decoded")
    store_dir = Path.join(data_dir, "store")
    # set variable
    :persistent_term.put(:data_dir, data_dir)
    :persistent_term.put(:block_dir, block_dir)
    :persistent_term.put(:decode_dir, decode_dir)
    :persistent_term.put(:store_dir, store_dir)
    # make folders
    File.mkdir(data_dir)
    File.mkdir(store_dir)
    File.mkdir(block_dir)
    File.mkdir(decode_dir)
  end
end
