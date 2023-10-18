defmodule EnvStore do
  require Sqlite

  def load(db_ref) do
    data = Sqlite.all("all_env")

    for [name, value] <- data do
      :persistent_term.put(name, :erlang.binary_to_term(value))
    end
  end

  def put(db_ref, name, value) do
    value = transform(name, value)
    :persistent_term.put({:env, name}, value)
    Sqlite.step("insert_env", [name, :erlang.term_to_binary(value)])
  end

  def delete(db_ref, name) do
    :persistent_term.erase({:env, name})
    Sqlite.step("delete_env", [name])
  end

  def owner, do: :persistent_term.get({:env, "OWNER"}, nil)

  def token_price do
    :persistent_term.get({:env, "TOKEN.PRICE"}, 50_000)
  end

  def validator_price do
    :persistent_term.get({:env, "VALIDATOR.PRICE"}, 100_000)
  end

  def jackpot_reward do
    :persistent_term.get({:env, "JACKPOT.REWARD"}, 100)
  end

  def network_fee do
    :persistent_term.get({:env, "NETWORK.FEE"}, 1)
  end

  def round_blocks do
    :persistent_term.get({:env, "ROUND.BLOCKS"}, 10)
  end

  def round_delegates do
    :persistent_term.get({:env, "ROUND.DELEGATES"}, 20)
  end

  defp transform("TOKEN.PRICE", x), do: if(is_integer(x) and x > 0, do: x, else: 50_000)

  defp transform("VALIDATOR.PRICE", x), do: if(is_integer(x) and x > 0, do: x, else: 100_000)

  defp transform("JACKPOT.REWARD", x), do: if(x in 1..100_000, do: x, else: 100)

  defp transform("NETWORK.FEE", x), do: if(is_integer(x) and x > 0, do: x, else: 1)

  defp transform("ROUND.BLOCKS", x), do: if(x in 1..100, do: x, else: 10)

  defp transform("ROUND.DELEGATES", x), do: if(x in 1..100, do: x, else: 20)
  defp transform(_, x), do: x
end
