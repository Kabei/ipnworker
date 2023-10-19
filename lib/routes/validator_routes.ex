defmodule Ipnworker.ValidatorRoutes do
  alias Ippan.Ecto.Validator
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> Validator.all()
    |> send_json()
  end

  get "/:id" do
    id
    |> Validator.one()
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
