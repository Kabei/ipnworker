defmodule Ippan.Funx.Wallet do
  require BalanceStore
  alias Ippan.{Address, Utils}

  def new(_, pubkey, sig_type, %{"vid" => validator_id, "fa" => fa, "fb" => fb}) do
    pubkey = Fast64.decode64(pubkey)
    id = Address.hash(sig_type, pubkey)
    tx = DetsPlux.tx(:wallet)
    DetsPlux.put(tx, {id, pubkey, sig_type, %{"vid" => validator_id, "fa" => fa, "fb" => fb}})
  end

  def subscribe(
        source = %{
          id: from,
          map: %{"fa" => fa, "fb" => fb},
          validator: %{owner: vOwner},
          size: size
        },
        validator_id
      ) do
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(dets, :balance)
    fees = Utils.calc_fees(fa, fb, size)

    case BalanceStore.pay_fee(from, vOwner, fees) do
      :error ->
        :error

      _ ->
        wdets = DetsPlux.get(:wallet)
        wtx = DetsPlux.tx(:wallet)
        DetsPlux.get_cache(wdets, wtx, from)
        DetsPlux.update_element(wtx, from, 3, %{"fa" => fa, "fb" => fb, "vid" => validator_id})
    end
  end
end
