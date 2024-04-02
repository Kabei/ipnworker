defmodule RegPay do
  @moduledoc """
  Payments types:
  0. Coinbase
  1. Round Reward
  2. Jackpot
  3. PayConnect
  100. Pay
  101. Refund
  200. Fees
  201. Reserve
  202. Expired
  300. Burn
  301. lock
  302. unlock
  303. drop coins
  400. PayStream
  401. Withdraw
  """

  @app Mix.Project.config()[:app]
  @table :payment
  @history Application.compile_env(@app, :history, false)
  @notify Application.compile_env(@app, :notify, false)

  if @history do
    def init do
      tid =
        :ets.new(@table, [
          :duplicate_bag,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      :persistent_term.put(@table, tid)
    end

    def terminate do
      tid = :persistent_term.get(@table)
      :ets.delete(tid)
      :persistent_term.erase(@table)
    end

    def coinbase(%{id: from, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {from, nonce, to, 0, token, amount})
    end

    def reload(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(@table), {from, nonce, from, 3, token, amount})
    end

    def payment(%{id: account, nonce: nonce}, from, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), [
        {account, nonce, to, 100, token, amount},
        {account, nonce, from, 100, token, -amount}
      ])
    end

    def refund(%{id: account, nonce: nonce}, from, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), [
        {account, nonce, to, 101, token, amount},
        {account, nonce, from, 101, token, -amount}
      ])
    end

    def fees(%{id: account, nonce: nonce}, from, validator, token, amount) do
      :ets.insert(:persistent_term.get(@table), [
        {account, nonce, validator, 200, token, amount},
        {account, nonce, from, 200, token, -amount}
      ])
    end

    def reserve(%{nonce: nonce}, from, token, amount) do
      :ets.insert(:persistent_term.get(@table), {from, nonce, nil, 201, token, -amount})
    end

    def expired(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(@table), {from, nonce, from, 202, token, -amount})
    end

    def drop(%{id: from, nonce: nonce}, token, amount) do
      :ets.insert(:persistent_term.get(@table), {from, nonce, from, 303, token, -amount})
    end

    def burn(%{id: account, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {account, nonce, to, 300, token, -amount})
    end

    def lock(%{id: account, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {account, nonce, to, 301, token, -amount})
    end

    def unlock(%{id: account, nonce: nonce}, to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {account, nonce, to, 302, token, amount})
    end

    def reward(to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {nil, nil, to, 1, token, amount})
    end

    def jackpot(to, token, amount) do
      :ets.insert(:persistent_term.get(@table), {nil, nil, to, 2, token, amount})
    end

    def stream(%{id: account, nonce: nonce}, service, payer, token, amount) do
      :ets.insert(:persistent_term.get(@table), [
        {account, nonce, payer, 400, token, -amount},
        {account, nonce, service, 400, token, amount}
      ])
    end

    def withdraw(%{id: account, nonce: nonce}, service, token, amount, tax) do
      :ets.insert(:persistent_term.get(@table), [
        {account, nonce, service, 401, token, -amount},
        {account, nonce, service, 300, token, -tax},
        {account, nonce, account, 401, token, amount}
      ])
    end
  else
    def init, do: :ok
    def terminate, do: :ok
    def coinbase(_, _, _, _), do: true
    def reload(_, _, _), do: true
    def payment(_, _, _, _, _), do: true
    def refund(_, _, _, _, _), do: true
    def expired(_, _, _), do: true
    def fees(_, _, _, _, _), do: true
    def reserve(_, _, _), do: true
    def drop(_, _, _), do: true
    def burn(_, _, _, _), do: true
    def lock(_, _, _, _), do: true
    def unlock(_, _, _, _), do: true
    def reward(_, _, _), do: true
    def jackpot(_, _, _), do: true
    def stream(_, _, _, _, _), do: true
    def withdraw(_, _, _, _, _), do: true
  end

  def commit(nil, _), do: nil

  if @notify do
    @pubsub :pubsub

    def commit(pg_conn, round_id) do
      tid = :persistent_term.get(@table)
      data = :ets.tab2list(tid)
      synced = :persistent_term.get(:status) == :synced

      Enum.each(
        data,
        fn {from, nonce, to, type, token, amount} ->
          PgStore.insert_pay(pg_conn, [from, nonce, to, round_id, type, token, amount])

          if synced and to do
            payload =
              %{
                "amount" => amount,
                "from" => from,
                "to" => to,
                "nonce" => nonce,
                "round" => round_id,
                "token" => token,
                "type" => type
              }
              |> MapUtil.drop_nils()

            Phoenix.PubSub.local_broadcast(@pubsub, "pay:#{to}", payload)
          end
        end
      )

      :ets.delete_all_objects(tid)
    end
  else
    def commit(pg_conn, round_id) do
      tid = :persistent_term.get(@table)
      data = :ets.tab2list(tid)

      Enum.each(data, fn {from, nonce, to, type, token, amount} ->
        PgStore.insert_pay(pg_conn, [from, nonce, to, round_id, type, token, amount])
      end)

      :ets.delete_all_objects(tid)
    end
  end
end
