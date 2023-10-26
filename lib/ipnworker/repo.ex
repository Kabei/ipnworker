defmodule Ipnworker.Repo do
  @app Mix.Project.config()[:app]

  use Ecto.Repo,
    otp_app: @app,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
