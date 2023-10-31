# defmodule Ipnworker.ClusterRoutes do
#   alias Ippan.Ecto.Node
#   use Plug.Router
#   import Ippan.Utils, only: [send_json: 1, fetch_query: 1]

#   @app Mix.Project.config()[:app]
#   @max_size Application.compile_env(@app, :message_max_size)

#   if Mix.env() == :dev do
#     use Plug.Debugger
#   end

#   plug(:match)
#   plug(:dispatch)

#   get "/node/all" do
#     fetch_query(conn)
#     |> Token.all()
#     |> send_json()
#   end

#   get "/node/total" do
#     n = Node.total()
#     send_resp(conn, 200, Integer.to_string(n))
#   end

#   get "/info" do
#     send_resp(conn, 200, "")
#   end

#   get "/node/:id" do
#     id
#     |> Token.one()
#     |> send_json()
#   end

#   post "/node/call" do
#     auth = get_req_header(conn, "auth")
#     {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

#     case check_mac(auth, body) do
#       true ->
#         nil

#       false ->
#         send_resp(conn, 401, "")
#     end
#   end

#   defp check_mac(auth, body) do
#     hash = Base.decode16!(auth, case: :mixed)
#     key = :persistent_term.get(:auth)
#     hash == :crypto.mac(:hmac, :sha256, key, Blake3.hash(body))
#   end

#   match _ do
#     send_resp(conn, 404, "Not found")
#   end
# end
