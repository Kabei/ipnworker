defmodule Ipnworker.AccountRoutes do
  use Plug.Router
  alias Ippan.Ecto.Balance
  alias Ippan.Utils
  import Ippan.Utils, only: [fetch_query: 1, json: 1, send_json: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/:id" do
    wallet = DetsPlux.get(:wallet)
    tx = DetsPlux.tx(wallet, :cache_wallet)

    case DetsPlux.get_cache(wallet, tx, id) do
      {pk, sig_type, map} ->
        nonce_db = DetsPlux.get(:nonce)
        tx = DetsPlux.tx(nonce_db, :cache_nonce)
        nonce = DetsPlux.get_cache(nonce_db, tx, id, 0)

        map
        |> Map.merge(%{
          "nonce" => nonce,
          "pubkey" => Utils.encode64(pk),
          "sig_type" => sig_type
        })
        |> json()

      _ ->
        send_resp(conn, 204, "")
    end
  end

  get "/:id/balance" do
    Balance.all(fetch_query(conn), id)
    |> send_json()
  end

  get "/:id/balance/:token" do
    db = DetsPlux.get(:balance)
    tx = DetsPlux.tx(db, :cache_balance)
    key = DetsPlux.tuple(id, token)
    {balance, map} = DetsPlux.get_cache(db, tx, key, {0, %{}})

    %{"balance" => balance, "map" => map} |> json()
  end

  get "/:id/nonce" do
    db = DetsPlux.get(:nonce)
    tx = DetsPlux.tx(db, :cache_nonce)
    nonce = DetsPlux.get_cache(db, tx, id, 0)
    send_resp(conn, 200, Integer.to_string(nonce))
  end

  head "/:id" do
    db = DetsPlux.get(:wallet)

    case DetsPlux.member?(db, id) do
      true -> send_resp(conn, 200, "")
      false -> send_resp(conn, 204, "")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
