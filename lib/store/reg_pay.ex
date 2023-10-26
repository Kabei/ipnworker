defmodule RegPay do
  # 0. Coinbase / Reward
  # 1. Pay
  # 2. Fees
  # 3. Burn
  @app Mix.Project.config()[:app]
  @master Application.compile_env(@app, :master, false)

  defmacro init do
    if @master do
      quote do
        tid = :ets.new(:payment, [:bag, :public, read_concurrency: true, write_concurrency: true])
        :persistent_term.put(:payment, tid)
      end
    end
  end

  defmacro coinbase(hash, to, token, amount) do
    if @master do
      quote location: :keep do
        :ets.insert(
          :payment,
          {unquote(hash), 0, nil, unquote(to), unquote(token), unquote(amount)}
        )
      end
    end
  end

  defmacro payment(hash, from, to, token, amount) do
    if @master do
      quote location: :keep do
        :ets.insert(
          :payment,
          {unquote(hash), 1, unquote(from), unquote(to), unquote(token), unquote(amount)}
        )
      end
    end
  end

  defmacro fees(hash, from, to, token, amount) do
    if @master do
      quote location: :keep do
        :ets.insert(
          :payment,
          {unquote(hash), 2, unquote(from), unquote(to), unquote(token), unquote(amount)}
        )
      end
    end
  end

  defmacro burn(hash, from, token, amount) do
    if @master do
      quote location: :keep do
        :ets.insert(
          :payment,
          {unquote(hash), 3, unquote(from), nil, unquote(token), unquote(amount)}
        )
      end
    end
  end

  defmacro commit_tx(ix, block_id) do
    quote location: :keep do
      Enum.each(:ets.lookup(:payment, var!(hash)), fn {_, type, from, to, token, amount} ->
        PgStore.insert_pay(var!(pg_conn), [
          unquote(ix),
          unquote(block_id),
          type,
          from,
          to,
          token,
          amount
        ])
      end)

      :ets.delete(:payment, var!(hash))
    end
  end

  defmacro commit_reward(round_id, to, token, amount) do
    if @master do
      quote location: :keep do
        PgStore.insert_pay(var!(pg_conn), [
          nil,
          unquote(round_id),
          0,
          nil,
          unquote(to),
          unquote(token),
          unquote(amount)
        ])
      end
    end
  end
end
