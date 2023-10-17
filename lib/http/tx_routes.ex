defmodule Ipnworker.TxRoutes do
  alias Ippan.Ecto.Tx
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> Tx.all()
    |> send_json()
  end

  get "/:block/:hash" do
    Tx.one(block, hash)
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
