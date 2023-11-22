defmodule Ipnworker.DomainRoutes do
  require Ippan.Domain
  alias Ippan.Ecto.Domain
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]
  require Sqlite

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

  head "/:name" do
    db_ref = :persistent_term.get(:main_ro)

    case Ippan.Domain.exists?(name) do
      true -> send_resp(conn, 200, "")
      false -> send_resp(conn, 204, "")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
