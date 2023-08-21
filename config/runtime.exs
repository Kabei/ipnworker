import Config

# Number of cores available
cpus = System.schedulers_online()

# Environment variables setup
http_port = System.get_env("HTTP_PORT", "8080") |> String.to_integer()

data_dir = System.get_env("DATA_DIR", "data")
kem_dir = System.get_env("KEM_DIR", "priv/kem.key")
falcon_dir = System.get_env("FALCON_DIR", "priv/falcon.key")
key_dir = System.get_env("KEY_DIR", "priv/secret.key")

# Folder cert
config :ipnworker, :kem_dir, kem_dir
config :ipnworker, :falcon_dir, falcon_dir
config :ipnworker, :key_dir, key_dir

# Node setup
config :ipnworker, :vid, System.get_env("VID", "0") |> String.to_integer()

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
