defmodule Ipnworker.ClusterRoutes do
  alias Ippan.Ecto.Node, as: NodeApi
  use Plug.Router
  import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

  # @app Mix.Project.config()[:app]
  # @json Application.compile_env(@app, :json)
  # @max_size Application.compile_env(@app, :message_max_size)

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  # post "/call" do
    # auth = get_req_header(conn, "auth")
    # {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

    # case check_mac(auth, body) do
    #   true ->
    #     with %{"method" => method, "data" => data} <- @json.decode!(body),
    #          :ok <- NodeApi.trigger(method, data) do
    #       send_resp(conn, 200, "")
    #     else
    #       _ ->
    #         send_resp(conn, 400, "Bad arguments")
    #     end

    #   false ->
    #     send_resp(conn, 401, "")
    # end
  # end

  get "/node/all" do
    fetch_query(conn)
    |> NodeApi.all()
    |> send_json()
  end

  get "/nodes" do
    n = NodeApi.total()
    send_resp(conn, 200, Integer.to_string(n))
  end

  # get "/info" do
  #   send_resp(conn, 200, "")
  # end

  get "/node/:id" do
    id
    |> NodeApi.one()
    |> send_json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # defp check_mac(auth, body) do
  #   key = :persistent_term.get(:auth)
  #   Base.decode16!(auth, case: :mixed) == :crypto.mac(:hmac, :sha3_256, key, body)
  # end
end
