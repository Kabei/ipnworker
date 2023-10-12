defmodule Ipnworker.Repo do
  use Ecto.Repo,
    otp_app: :ipnworker,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
