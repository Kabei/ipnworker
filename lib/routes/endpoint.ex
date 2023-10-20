defmodule Ipnworker.Endpoint do
  use Plug.Builder

  if Mix.env() == :dev do
    plug(Plug.Logger)
  end

  # plug(Plug.SSL, rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port])
  plug(Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto])

  # plug(Plug.Cors)

  plug(Ipnworker.Router)
end
