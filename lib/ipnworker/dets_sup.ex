defmodule Ippan.DetsSup do
  use Supervisor

  def start_link(children) do
    Supervisor.start_link(__MODULE__, children, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    store_dir = :persistent_term.get(:store_dir)
    wallet_path = Path.join(store_dir, "wallet.dx")
    nonce_path = Path.join(store_dir, "nonce.dx")
    balance_path = Path.join(store_dir, "balance.dx")
    stats_path = Path.join(store_dir, "stats.dx")

    children = [
      {DetsPlux, [id: :wallet, file: wallet_path]},
      {DetsPlux, [id: :nonce, file: nonce_path]},
      {DetsPlux, [id: :balance, file: balance_path]},
      {DetsPlux, [id: :stats, file: stats_path]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def refs(number) do
    x = rem(number, 7)

    %{
      wallet: String.to_atom("wallet#{x}"),
      balance: String.to_atom("balance#{x}"),
      nonce: String.to_atom("nonce#{x}"),
      stats: String.to_atom("stats#{x}"),
      supply: String.to_atom("supply#{x}")
    }
  end

  def cache do
    %{
      wallet: :cache_wallet,
      balance: :cache_balance,
      nonce: :cache_nonce,
      stats: :cahce_stats,
      supply: :cache_supply
    }
  end

  def real do
    %{
      wallet: :wallet,
      balance: :balance,
      nonce: :nonce,
      stats: :stats,
      supply: :supply
    }
  end

  def close(txs) do
    for {_name, ref} <- txs do
      case :persistent_term.get({:txs, ref}) do
        nil ->
          false

        table ->
          case :ets.whereis(table) do
            :undefined ->
              :ok

            tid ->
              :ets.delete(tid)
          end
      end
    end
  end
end
