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
  @master Application.compile_env(@app, :master, false)

  defmacro init do
    if @master do
      quote do
        tid =
          :ets.new(:payment, [
            :duplicate_bag,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])

        :persistent_term.put(:payment, tid)
      end
    end
  end

  defmacro reg_coinbase(to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 0, nil, unquote(to), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_refund(from, to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 101, unquote(to), unquote(from), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_payment(from, to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 100, unquote(from), unquote(to), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_fees(from, to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 200, unquote(from), unquote(to), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_delete(from, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 201, unquote(from), nil, unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_burn(from, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 300, unquote(from), nil, unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_lock(to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash, id: from} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 400, from, unquote(to), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  defmacro reg_unlock(to, token, amount) do
    if @master do
      quote location: :keep do
        %{hash: hash, id: from} = var!(source)

        :ets.insert(
          :persistent_term.get(:payment),
          {hash, 401, from, unquote(to), unquote(token), unquote(amount)}
        )
      end
    else
      quote do
        var!(source)
      end
    end
  end

  def commit_tx(nil, _, _, _), do: nil

  def commit_tx(pg_conn, ets_payment, hash, ix, block_id) do
    Enum.each(:ets.lookup(ets_payment, hash), fn {_, type, from, to, token, amount} ->
      PgStore.insert_pay(pg_conn, [
        ix,
        block_id,
        type,
        from,
        to,
        token,
        amount
      ])
      |> IO.inspect()
    end)

    :ets.delete(ets_payment, hash)
  end

  defmacro commit_reward(round_id, to, token, amount) do
    if @master do
      quote location: :keep do
        PgStore.insert_pay(var!(pg_conn), [
          nil,
          unquote(round_id),
          1,
          nil,
          unquote(to),
          unquote(token),
          unquote(amount)
        ])
      end
    end
  end
end
