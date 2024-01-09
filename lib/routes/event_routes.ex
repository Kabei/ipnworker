defmodule Ipnworker.EventRoutes do
  use Plug.Router

  @pubsub :pubsub

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/rounds" do
    SSE.stream(conn, @pubsub, "round.new", once: false, timeout: 30_000)
  end

  get "/blocks" do
    SSE.stream(conn, @pubsub, "block.new", once: false, timeout: 30_000)
  end

  get "/validators" do
    SSE.stream(conn, @pubsub, "validator", once: false, timeout: :infinity)
  end

  get "/round/:id" do
    SSE.stream(conn, @pubsub, "round:#{id}", timeout: 20_000)
  end

  get "/mempool" do
    SSE.stream(conn, @pubsub, "mempool", timeout: 20_000)
  end

  get "/block/:id" do
    SSE.stream(conn, @pubsub, "block:#{id}", timeout: 20_000)
  end

  get "/payments/:account" do
    SSE.stream(conn, @pubsub, "payments:#{account}", once: false, timeout: :infinity)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
