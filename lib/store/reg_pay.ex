defmodule RegPay do
  # Event Transf
  # 0. Coinbase
  # 1. Reward
  # 2. Jackpot
  # 100. Pay
  # 101. Refund
  # 200. Fees
  # 201. Delete
  # 300. Burn
  # 301. lock
  # 302. unlock

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

    def coinbase(source, to, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {nil, nonce, to, block, 0, token, amount})
    end

    def refund(source, from, to, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, block, 1, token, amount})
    end

    def payment(source, from, to, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, block, 100, token, amount})
    end

    def fees(source, from, to, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, block, 200, token, amount})
    end

    def delete(source, from, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, nil, block, 201, token, amount})
    end

    def burn(source, from, token, amount) do
      %{block: block, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, nil, block, 300, token, amount})
    end

    def lock(source, to, token, amount) do
      %{block: block, id: from, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, block, 301, token, amount})
    end

    def unlock(source, to, token, amount) do
      %{block: block, id: from, nonce: nonce} = source
      :ets.insert(:persistent_term.get(:payment), {from, nonce, to, block, 302, token, amount})
    end
  else
    def init, do: :ok
    def coinbase(_, _, _, _), do: :ok
    def refund(_, _, _, _, _), do: :ok
    def payment(_, _, _, _, _), do: :ok
    def fees(_, _, _, _, _), do: :ok
    def delete(_, _, _, _), do: :ok
    def burn(_, _, _, _), do: :ok
    def lock(_, _, _, _), do: :ok
    def unlock(_, _, _, _), do: :ok
  end

  def commit(nil), do: nil

  def commit(pg_conn) do
    tid = :persistent_term.get(:payment)

    :ets.tab2list(tid)
    |> Enum.each(fn {from, nonce, to, block, type, token, amount} ->
      PgStore.insert_pay(pg_conn, [from, nonce, to, block, type, token, amount])
    end)

    :ets.delete_all_objects(tid)
  end
end
