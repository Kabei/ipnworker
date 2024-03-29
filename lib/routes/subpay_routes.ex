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

  head "/:id/:payer" do
    db_ref = :persistent_term.get(:main_ro)

    case SubPay.has?(db_ref, id, payer) do
      true -> send_resp(conn, 200, "")
      false -> send_resp(conn, 204, "")
    end
  end

  head "/:id/:payer/:token" do
    db_ref = :persistent_term.get(:main_ro)

    case SubPay.has?(db_ref, id, payer, token) do
      true -> send_resp(conn, 200, "")
      false -> send_resp(conn, 204, "")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
