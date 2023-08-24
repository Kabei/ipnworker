defmodule Ippan.Events do
  alias Ippan.Event

  alias Ippan.Func.{
    Env,
    Balance,
    Tx,
    Validator,
    Token,
    Domain,
    Dns,
    Wallet
  }

  @events [
    %Event{
      id: 0,
      name: "wallet.sub",
      base: :wallet,
      mod: Wallet,
      fun: :subscribe,
      before: :pre_sub,
      deferred: true,
      validator: false
    },
    %Event{
      id: 1,
      name: "wallet.unsub",
      base: :wallet,
      mod: Wallet,
      fun: :unsubscribe,
      deferred: false
    },
    %Event{
      id: 50,
      name: "env.set",
      base: :env,
      mod: Env,
      fun: :set,
      before: :pre_set,
      deferred: true
    },
    %Event{
      id: 51,
      name: "env.delete",
      base: :env,
      mod: Env,
      before: :pre_delete,
      fun: :delete,
      deferred: true
    },
    %Event{
      id: 100,
      name: "validator.new",
      base: :validator,
      mod: Validator,
      fun: :new,
      before: :pre_new,
      deferred: true
    },
    %Event{
      id: 101,
      name: "validator.update",
      base: :validator,
      mod: Validator,
      fun: :update,
      before: :pre_update,
      deferred: true
    },
    %Event{
      id: 102,
      name: "validator.delete",
      base: :validator,
      mod: Validator,
      fun: :delete,
      before: :pre_delete,
      deferred: true
    },
    %Event{
      id: 200,
      name: "token.new",
      base: :token,
      mod: Token,
      fun: :new,
      before: :pre_new,
      deferred: true
    },
    %Event{
      id: 201,
      name: "token.update",
      base: :token,
      mod: Token,
      fun: :update
    },
    %Event{
      id: 202,
      name: "token.delete",
      base: :token,
      mod: Token,
      fun: :delete
    },
    %Event{
      id: 250,
      name: "balance.lock",
      base: :balance,
      mod: Balance,
      fun: :lock
    },
    %Event{
      id: 251,
      name: "balance.unlock",
      base: :balance,
      mod: Balance,
      fun: :unlock
    },
    %Event{
      id: 300,
      name: "tx.coinbase",
      base: :tx,
      mod: Tx,
      fun: :coinbase
    },
    %Event{
      id: 301,
      name: "tx.send",
      base: :tx,
      mod: Tx,
      fun: :send
    },
    %Event{
      id: 302,
      name: "tx.burn",
      base: :tx,
      mod: Tx,
      fun: :burn
    },
    %Event{
      id: 303,
      name: "tx.refund",
      mod: Tx,
      base: :tx,
      fun: :refund
    },
    %Event{
      id: 304,
      name: "tx.refundable",
      mod: Tx,
      base: :tx,
      fun: :send_refundable
    },
    %Event{
      id: 400,
      name: "domain.new",
      mod: Domain,
      base: :domain,
      fun: :new,
      before: :pre_new,
      deferred: true
    },
    %Event{
      id: 401,
      name: "domain.update",
      base: :domain,
      mod: Domain,
      fun: :update
    },
    %Event{
      id: 402,
      name: "domain.delete",
      base: :domain,
      mod: Domain,
      fun: :delete
    },
    %Event{
      id: 403,
      name: "domain.renew",
      base: :domain,
      mod: Domain,
      fun: :renew
    },
    %Event{
      id: 500,
      name: "dns.new",
      base: :dns,
      mod: Dns,
      fun: :new
    },
    %Event{
      id: 501,
      name: "dns.update",
      base: :dns,
      mod: Dns,
      fun: :update
    },
    %Event{
      id: 502,
      name: "dns.delete",
      base: :dns,
      mod: Dns,
      fun: :delete
    }
  ]

  @spec lookup(event_id :: non_neg_integer()) :: map() | :undefined

  for struct <- @events do
    model = Map.from_struct(struct) |> Map.delete(:__struct__)

    quote do
      def lookup(unquote(model).id) do
        unquote(model)
      end
    end
  end

  def lookup(_), do: :undefined
end
