defmodule Ipnworker.JackpotRoutes do
  alias Ippan.Ecto.Jackpot
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> Jackpot.all()
    |> send_json()
  end

  get "/last" do
    Jackpot.last()
    |> send_json()
  end

  get "/:id" do
    id
    |> Jackpot.one()
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
