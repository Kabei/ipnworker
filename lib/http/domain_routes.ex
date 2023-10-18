defmodule Ipnworker.DomainRoutes do
  alias Ippan.Ecto.Domain
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> Domain.all()
    |> send_json()
  end

  get "/:name" do
    Domain.one(name)
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
