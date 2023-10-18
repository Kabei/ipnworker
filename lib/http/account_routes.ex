defmodule Ipnworker.AccountRoutes do
  use Plug.Router
  alias Ippan.Utils
  import Ippan.Utils, only: [json: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/:id" do
    dets = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(dets, :cache_wallet)

    case DetsPlux.get_cache(dets, tx, id) do
      {pk, v} ->
        %{"pubkey" => Utils.encode64(pk), "validator" => v} |> json

      _ ->
        send_resp(conn, 204, "")
    end
  end

  get "/:id/nonce" do
    dets = DetsPlux.get(:nonce)
    tx = DetsPlux.tx(dets, :cache_nonce)
    nonce = DetsPlux.get_cache(dets, tx, id, 0)
    send_resp(conn, 200, Integer.to_string(nonce))
  end

  get "/:id/balance" do
    dets = DetsPlux.get(:balance)
    tx = DetsPlux.tx(dets, :cache_balance)
    {balance, lock} = DetsPlux.get_cache(dets, tx, id, {0, 0})

    %{"balance" => balance, "lock" => lock} |> json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
