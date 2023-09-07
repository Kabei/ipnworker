import Config

# Number of cores available
cpus = System.schedulers_online()

# Environment variables setup
port = System.get_env("PORT", "5815") |> String.to_integer()
cluster_port = System.get_env("CLUSTER_PORT", "4848") |> String.to_integer()
http_port = System.get_env("HTTP_PORT", "8080") |> String.to_integer()

# HTTP server
config :ipnworker, :http,
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
      send_timeout: 10_000,
      send_timeout_close: true,
      reuseaddr: true
    ]
  ]

# Cluster setup
config :ipnworker, :cluster,
  handler_module: Ippan.ClusterServer,
  transport_module: ThousandIsland.Transports.TCP,
  num_acceptors: max(cpus, 10),
  port: cluster_port,
  transport_options: [
    backlog: 1024,
    nodelay: true,
    linger: {true, 30},
    send_timeout: 30_000,
    send_timeout_close: true,
    reuseaddr: true,
    packet: 2,
    packet_size: 64_000
  ]

# remote database setup
config :ipnworker, :repo,
  hostname: System.get_env("PGHOST", "localhost"),
  database: System.get_env("PGDATABASE", "ippan"),
  username: System.get_env("PGUSER", "kambei"),
  password: System.get_env("PGPASSWORD", "secret"),
  port: System.get_env("PGPORT", "5432") |> String.to_integer(),
  pool_size: System.get_env("PGPOOL", "1") |> String.to_integer(),
  prepare: :unnamed,
  parameters: [plan_cache_mode: "force_custom_plan"],
  timeout: 60_000

# NTP servers
config :ipnworker, :ntp_servers, [
  ~c"0.north-america.pool.ntp.org",
  ~c"1.north-america.pool.ntp.org",
  ~c"2.north-america.pool.ntp.org",
  ~c"0.europe.pool.ntp.org",
  ~c"1.europe.pool.ntp.org",
  ~c"2.europe.pool.ntp.org",
  ~c"0.asia.pool.ntp.org",
  ~c"1.asia.pool.ntp.org",
  ~c"2.asia.pool.ntp.org",
  ~c"0.oceania.pool.ntp.org",
  ~c"0.africa.pool.ntp.org",
  ~c"hora.roa.es",
  ~c"time.google.com",
  ~c"time.cloudflare.com",
  ~c"time.windows.com"
]

config :ipnworker, :dns_resolve,
  alt_nameservers: [
    {{8, 8, 8, 8}, 53},
    {{1, 0, 0, 1}, 53},
    {{208, 67, 220, 220}, 53}
  ],
  nameservers: [
    {{1, 1, 1, 1}, 53},
    {{8, 8, 4, 4}, 53},
    {{9, 9, 9, 9}, 53},
    {{208, 67, 222, 222}, 53}
  ],
  timeout: 5_000
