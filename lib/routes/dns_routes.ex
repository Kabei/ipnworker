defmodule Ipnworker.DnsRoutes do
  alias Ippan.Ecto.DNS
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/all" do
    fetch_query(conn)
    |> DNS.all()
    |> send_json()
  end

  get "/:domain/:hash" do
    DNS.one(domain, hash)
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
