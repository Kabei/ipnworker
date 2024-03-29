defmodule BalanceStore do
  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)

  defmacro requires!(db, tx, key, value) do
    quote bind_quoted: [db: db, tx: tx, key: key, value: value], location: :keep do
      DetsPlux.get_cache(db, tx, key, {0, %{}})

      if DetsPlux.update_counter(tx, key, {2, -value}) < 0 do
        DetsPlux.update_counter(tx, key, {2, value})
        raise IppanError, "Insufficient balance"
      end
    end
  end

  defmacro multi_requires!(db, tx, key_value_list) do
    quote bind_quoted: [db: db, tx: tx, list: key_value_list], location: :keep do
      Enum.reduce(list, [], fn kv = {key, value}, acc ->
        DetsPlux.get_cache(db, tx, key, {0, %{}})

        if DetsPlux.update_counter(tx, key, {2, -value}) < 0 do
          DetsPlux.update_counter(tx, key, {2, value})

          Enum.each(acc, fn {key, value} ->
            DetsPlux.update_counter(tx, key, {2, value})
          end)

          raise IppanError, "Insufficient balance"
        else
          [kv | acc]
        end
      end)
    end
  end

  defmacro load(account_id, token_id) do
    quote bind_quoted: [account: account_id, token: token_id] do
      balance = DetsPlux.tuple(account, token)
      DetsPlux.get_cache(var!(db), var!(tx), balance, {0, %{}})
      balance
    end
  end

  defmacro make(account_id, token_id) do
    quote bind_quoted: [account: account_id, token: token_id] do
      DetsPlux.tuple(account, token)
    end
  end

  defmacro pay(from, token, amount, do: expression) do
    quote bind_quoted: [amount: amount, from: from, token: token, expression: expression],
          location: :keep do
      balance = BalanceStore.load(from, token)

      if DetsPlux.update_counter(var!(tx), balance, {2, -amount}) >= 0 do
        expression
      else
        DetsPlux.update_counter(var!(tx), balance, {2, amount})
        :error
      end
    end
  end

  defmacro pay(from, token, amount, fees, do: expression) do
    quote bind_quoted: [
            amount: amount,
            fees: fees,
            from: from,
            token: token,
            expression: expression
          ],
          location: :keep do
      balance = BalanceStore.load(from, token)

      if @token == token do
        total = amount + fees

        if DetsPlux.update_counter(var!(tx), balance, {2, -total}) >= 0 do
          expression
        else
          DetsPlux.update_counter(var!(tx), balance, {2, total})
          :error
        end
      else
        balance_native = BalanceStore.load(from, @token)

        if DetsPlux.update_counter(var!(tx), balance, {2, -amount}) >= 0 do
          if DetsPlux.update_counter(var!(tx), balance_native, {2, -fees}) >= 0 do
            expression
          else
            DetsPlux.update_counter(var!(tx), balance, {2, amount})
            DetsPlux.update_counter(var!(tx), balance_native, {2, fees})
            :error
          end
        else
          DetsPlux.update_counter(var!(tx), balance, {2, amount})
          :error
        end
      end
    end
  end

  defmacro pay2(outputs, do: expression) do
    quote bind_quoted: [outputs: outputs, expression: expression],
          location: :keep do
      Enum.reduce_while(outputs, [], fn {from, token, amount}, acc ->
        balance = BalanceStore.load(from, token)

        if DetsPlux.update_counter(var!(tx), balance, {2, -amount}) >= 0 do
          DetsPlux.update_counter(var!(tx), balance, {2, amount})
          Enum.each(acc, fn {b, a} -> DetsPlux.update_counter(var!(tx), b, {2, a}) end)
          {:cont, [{balance, amount} | acc]}
        else
          {:halt, :error}
        end
      end)
      |> case do
        :error -> :error
        _ -> expression
      end
    end
  end

  defmacro send(from, to, token, amount) do
    quote bind_quoted: [from: from, to: to, token: token, amount: amount], location: :keep do
      balance = DetsPlux.tuple(to, token)
      DetsPlux.get_cache(var!(db), var!(tx), balance, {0, %{}})
      DetsPlux.update_counter(var!(tx), balance, {2, amount})
      RegPay.payment(var!(source), from, to, token, amount)
    end
  end

  defmacro refund(from, old_sender, token, amount) do
    quote bind_quoted: [from: from, to: old_sender, token: token, amount: amount],
          location: :keep do
      balance_key = DetsPlux.tuple(from, token)
      DetsPlux.get_cache(var!(db), var!(tx), balance_key, {0, %{}})

      if DetsPlux.update_counter(var!(tx), balance_key, {2, -amount}) >= 0 do
        to_balance_key = DetsPlux.tuple(to, token)
        DetsPlux.get_cache(var!(db), var!(tx), to_balance_key, {0, %{}})
        DetsPlux.update_counter(var!(tx), to_balance_key, {2, amount})
        RegPay.refund(var!(source), from, to, token, amount)
      else
        DetsPlux.update_counter(var!(tx), balance_key, {2, amount})
        :error
      end
    end
  end

  defmacro fees(from, validator_balance_id, fees) do
    quote bind_quoted: [
            from: from,
            balance: validator_balance_id,
            fees: fees,
            token: @token
          ],
          location: :keep do
      DetsPlux.update_counter(var!(tx), balance, {2, fees})
      RegPay.fees(var!(source), from, var!(vOwner), token, fees)
    end
  end

  defmacro reserve(from, amount) do
    quote bind_quoted: [from: from, token: @token, amount: amount], location: :keep do
      if amount > 0 do
        supply = TokenSupply.jackpot()
        TokenSupply.add(supply, amount)

        RegPay.reserve(var!(source), from, token, amount)
      end
    end
  end

  defmacro burn(account, token, amount) do
    quote bind_quoted: [account: account, token: token, amount: amount],
          location: :keep do
      if amount > 0 do
        supply = TokenSupply.new(token)
        TokenSupply.subtract(supply, amount)

        RegPay.burn(var!(source), account, token, amount)
      end
    end
  end

  defmacro coinbase(account, token, value) do
    quote bind_quoted: [account: account, token: token, value: value], location: :keep do
      key = DetsPlux.tuple(account, token)
      DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})
      DetsPlux.update_counter(var!(tx), key, {2, value})

      RegPay.coinbase(var!(source), account, token, value)
    end
  end

  defmacro reload(target, token, value) do
    quote bind_quoted: [target: target, token: token, value: value], location: :keep do
      DetsPlux.update_counter(var!(tx), target, {2, value})
      supply = TokenSupply.new(token)
      TokenSupply.add(supply, value)

      RegPay.reload(var!(source), var!(token_id), value)
    end
  end

  defmacro expired(target, token, value) do
    quote bind_quoted: [target: target, value: value, token: token],
          location: :keep do
      DetsPlux.update_counter(var!(tx), target, {2, -value})
      supply = TokenSupply.new(token)
      TokenSupply.subtract(supply, value)

      RegPay.expired(var!(source), token, value)
    end
  end

  defmacro lock(to, token, value) do
    quote bind_quoted: [to: to, token: token, value: value], location: :keep do
      key = DetsPlux.tuple(to, token)
      {balance, map} = DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})

      if balance >= value do
        lock = Map.get(map, "lock", 0)
        map = Map.put(map, "lock", lock + value)
        DetsPlux.update_counter(var!(tx), key, [{2, -value}])
        DetsPlux.update_element(var!(tx), key, 3, map)

        RegPay.lock(var!(source), to, token, value)
      else
        :error
      end
    end
  end

  defmacro unlock(to, token, value) do
    quote bind_quoted: [to: to, token: token, value: value], location: :keep do
      key = DetsPlux.tuple(to, token)
      {balance, map} = DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})
      lock = Map.get(map, "lock", 0)

      if lock >= value do
        result = lock - value

        map =
          if result > 0, do: Map.put(map, "lock", result), else: Map.delete(map, "lock")

        DetsPlux.update_counter(var!(tx), key, [{2, value}])
        DetsPlux.update_element(var!(tx), key, 3, map)

        RegPay.unlock(var!(source), to, token, value)
      else
        :error
      end
    end
  end

  defmacro pay_fee(from, to, total_fees) do
    quote bind_quoted: [from: from, to: to, token: @token, total_fees: total_fees],
          location: :keep do
      if to != from do
        key = DetsPlux.tuple(from, token)
        {balance, _map} = DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})

        result = balance - total_fees

        if result >= 0 do
          to_key = DetsPlux.tuple(to, token)
          DetsPlux.get_cache(var!(db), var!(tx), to_key, {0, %{}})

          reserve = Ippan.Utils.calc_reserve(total_fees)
          fees = total_fees - reserve

          DetsPlux.update_counter(var!(tx), key, {2, -total_fees})
          DetsPlux.update_counter(var!(tx), to_key, {2, fees})

          RegPay.fees(var!(source), from, to, token, fees)
          BalanceStore.reserve(from, reserve)
        else
          :error
        end
      else
        BalanceStore.pay_burn(from, total_fees)
      end
    end
  end

  defmacro pay_burn(from, value) do
    quote bind_quoted: [from: from, token: @token, value: value],
          location: :keep do
      key = DetsPlux.tuple(from, token)
      DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})

      if DetsPlux.update_counter(var!(tx), key, {2, -value}) >= 0 do
        supply = TokenSupply.new(token)
        TokenSupply.subtract(supply, value)

        RegPay.burn(var!(source), from, token, value)
      else
        DetsPlux.update_counter(var!(tx), key, {2, value})
        :error
      end
    end
  end

  defmacro pay_burn(from, token, value) do
    quote bind_quoted: [from: from, token: token, value: value],
          location: :keep do
      key = DetsPlux.tuple(from, token)
      DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})

      if DetsPlux.update_counter(var!(tx), key, {2, -value}) >= 0 do
        supply = TokenSupply.new(token)
        TokenSupply.subtract(supply, value)

        RegPay.burn(var!(source), from, token, value)
      else
        DetsPlux.update_counter(var!(tx), key, {2, value})
        :error
      end
    end
  end

  defmacro pay_drop(from, token, value) do
    quote bind_quoted: [from: from, token: token, value: value],
          location: :keep do
      key = DetsPlux.tuple(from, token)
      DetsPlux.get_cache(var!(db), var!(tx), key, {0, %{}})

      if DetsPlux.update_counter(var!(tx), key, {2, -value}) >= 0 do
        supply = TokenSupply.new(token)
        TokenSupply.subtract(supply, value)

        RegPay.drop(var!(source), token, value)
      else
        DetsPlux.update_counter(var!(tx), key, {2, value})
        :error
      end
    end
  end

  defmacro stream(account, payer, service, token, amount) do
    quote bind_quoted: [
            account: account,
            payer: payer,
            amount: amount,
            service: service,
            token: token
          ],
          location: :keep do
      balance = DetsPlux.tuple(account, token)
      DetsPlux.get_cache(var!(db), var!(tx), balance, {0, %{}})

      DetsPlux.update_counter(var!(tx), balance, {2, amount})
      RegPay.stream(var!(source), account, payer, token, amount)
    end
  end

  defmacro withdraw(service_id, account, token, total_spent, received) do
    quote bind_quoted: [
            account: account,
            service: service_id,
            token: token,
            spent: total_spent,
            received: received
          ],
          location: :keep do
      balance = DetsPlux.tuple(account, token)
      DetsPlux.get_cache(var!(db), var!(tx), balance, {0, %{}})
      DetsPlux.update_counter(var!(tx), balance, {2, received})
      RegPay.withdraw(var!(source), service, token, spent, received)
    end
  end

  defmacro income(db, tx, account, token, value) do
    quote bind_quoted: [db: db, tx: tx, account: account, token: token, value: value],
          location: :keep do
      key = DetsPlux.tuple(account, token)
      DetsPlux.get_cache(db, tx, key, {0, %{}})
      DetsPlux.update_counter(tx, key, {2, value})
    end
  end
end
