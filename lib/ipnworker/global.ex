defmodule Global do
  import Ippan.Utils, only: [to_atom: 1]

  defmacro miner do
    quote do
      Default.get(:miner)
    end
  end

  defmacro owner do
    quote do
      Default.get(:owner)
    end
  end

  defmacro pubkey do
    quote do
      Default.get(:privkey)
    end
  end

  defmacro privkey do
    quote do
      Default.get(:privkey)
    end
  end

  defmacro owner?(id) do
    quote do
      Default.get(:owner, nil) == unquote(id)
    end
  end

  defmacro validator_id do
    quote do
      Default.get(:vid)
    end
  end

  defmacro expiry_time do
    quote do
      Default.get(:expiry_time)
    end
  end

  def update(new_owner) do
    GlobalConst.new(Default, %{
      owner: new_owner,
      miner: System.get_env("MINER") |> to_atom(),
      pubkey: Application.get_env(:ipnworker, :pubkey),
      privkey: Application.get_env(:ipnworker, :privkey),
      vid: Application.get_env(:ipnworker, :vid),
      expiry_time: Default.get(:expiry_time)
    })
  end
end
