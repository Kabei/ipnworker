defmodule RegPay do
  # Event Transf
  # 0. Coinbase
  # 1. Round Reward
  # 2. Jackpot
  # 3. Reload
  # 100. Pay
  # 101. Refund
  # 200. Fees
  # 201. Reserve
  # 300. Burn
  # 301. lock
  # 302. unlock
  # 303. drop coins

  @app Mix.Project.config()[:app]
  @history Application.compile_env(@app, :history)

  if @history do
    def init do
      tid =
        :ets.new(:payment, [
          :duplicate_bag,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      :persistent_term.put(:payment, tid)
    end

    def coinbase(%{id: from, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 0, token, amount})
    end

    def reload(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {nil, nonce, from, 3, token, amount})
    end

    def payment(%{nonce: nonce}, from, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 100, token, amount})
    end

    def refund(%{nonce: nonce}, from, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 101, token, amount})
    end

    def fees(%{id: from, nonce: nonce}, _from, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 200, token, amount})
    end

    def reserve(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, nil, 201, token, amount})
    end

    def expiry(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, nil, 202, token, amount})
    end

    def drop(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, nil, 303, token, amount})
    end

    def burn(%{id: from, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 300, token, amount})
    end

    def lock(%{id: from, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 301, token, amount})
    end

    def unlock(%{id: from, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, 302, token, amount})
    end

    def reward(to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {nil, nil, to, 1, token, amount})
    end

    def jackpot(to, token, amount) do
      :ets.insert(:persistent_term.get(:payment), {nil, nil, to, 2, token, amount})
    end
  else
    def init, do: :ok
    def coinbase(_, _, _, _), do: true
    def reload(_, _, _), do: true
    def payment(_, _, _, _, _), do: true
    def refund(_, _, _, _, _), do: true
    def expiry(_, _, _), do: true
    def fees(_, _, _, _, _), do: true
    def reserve(_, _, _), do: true
    def drop(_, _, _), do: true
    def burn(_, _, _, _), do: true
    def lock(_, _, _, _), do: true
    def unlock(_, _, _, _), do: true
    def reward(_, _, _), do: true
    def jackpot(_, _, _), do: true
  end

  def commit(nil, _), do: nil

  def commit(pg_conn, round_id) do
    tid = :persistent_term.get(:payment)

    :ets.tab2list(tid)
    |> Enum.each(fn {from, nonce, to, type, token, amount} ->
      PgStore.insert_pay(pg_conn, [from, nonce, to, round_id, type, token, amount])
    end)

    :ets.delete_all_objects(tid)
  end
end
