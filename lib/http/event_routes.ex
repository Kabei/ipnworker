defmodule Ipnworker.EventRoutes do
  use Plug.Router

  @pubsub :pubsub

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/rounds" do
    SSE.stream(conn, @pubsub, "round.new", once: false, timeout: 99_000)
  end

  get "/blocks" do
    SSE.stream(conn, @pubsub, "block.new", once: false, timeout: 99_000)
  end

  get "/jackpot" do
    SSE.stream(conn, @pubsub, "block.new", once: false, timeout: 99_000)
  end

  get "/round/:id" do
    SSE.stream(conn, @pubsub, "round:#{id}", timeout: 60_000)
  end

  get "/block/:id" do
    SSE.stream(conn, @pubsub, "block:#{id}", timeout: 60_000)
  end
end
