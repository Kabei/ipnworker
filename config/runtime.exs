import Config

# Number of cores available
cpus = System.schedulers_online()

# Environment variables setup
cluster_port = System.get_env("CLUSTER_PORT", "4848") |> String.to_integer()
http_port = System.get_env("HTTP_PORT", "8080") |> String.to_integer()
x_http_port = System.get_env("X_HTTP_PORT", "8080") |> String.to_integer()

# HTTP server
config :ipnworker, :http,
  plug: Ipnworker.Endpoint,
  scheme: :http,
  port: http_port,
  http_1_options: [
    compress: false
  ],
  thousand_island_options: [
    num_acceptors: 100,
    read_timeout: 60_000,
    num_connections: 16_384,
    max_connections_retry_count: 5,
    max_connections_retry_wait: 1000,
    shutdown_timeout: 60_000,
    transport_options: [
      backlog: 1024,
      nodelay: true,
      linger: {true, 30},
      send_timeout: 20_000,
      send_timeout_close: true,
      reuseaddr: true
    ]
  ]

# Cluster setup
config :ipnworker, :cluster,
  handler_module: Ippan.ClusterServer,
  transport_module: ThousandIsland.Transports.TCP,
  num_acceptors: 100,
  port: cluster_port,
  transport_options: [
    backlog: 1024,
    nodelay: true,
    linger: {true, 30},
    send_timeout: 30_000,
    send_timeout_close: true,
    reuseaddr: true,
    packet: 4,
    packet_size: 1_000_000
  ]

# remote database setup
config :ipnworker, ecto_repos: [Ipnworker.Repo]

config :ipnworker, Ipnworker.Repo,
  hostname: System.get_env("PGHOST", "localhost"),
  database: System.get_env("PGDATABASE", "ippan"),
  username: System.get_env("PGUSER", "kambei"),
  password: System.get_env("PGPASSWORD", "secret"),
  port: System.get_env("PGPORT", "5432") |> String.to_integer(),
  pool_size: System.get_env("PGPOOL", "4") |> String.to_integer(),
  wsize: System.get_env("WPOOL", "2") |> String.to_integer(),
  prepare: :unnamed,
  parameters: [plan_cache_mode: "force_custom_plan"]

config :ipnworker, :x_http_port, x_http_port
