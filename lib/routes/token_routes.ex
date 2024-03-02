defmodule Ipnworker.TokenRoutes do
  alias Ippan.Ecto.Token
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> Token.all()
    |> send_json()
  end

  get "/:id" do
    id
    |> Token.one()
    |> send_json()
  end

  get "/:id/supply" do
    supply = TokenSupply.cache(id)
    amount = TokenSupply.get(supply)
    send_resp(conn, 200, Integer.to_string(amount))
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
