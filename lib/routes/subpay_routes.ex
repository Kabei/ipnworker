defmodule Ipnworker.SubPayRoutes do
  alias Ippan.Ecto.SubPay, as: SubPayEcto
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> SubPayEcto.all()
    |> send_json()
  end

  get "/:payer/total" do
    db_ref = :persistent_term.get(:main_ro)
    SubPay.total(db_ref, payer)
    |> send_json()
  end

  get "/:id/:payer/:token" do
    SubPayEcto.one(id, payer, token)
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
