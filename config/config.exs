import Config

http_port = System.get_env("HTTP_PORT", "8080") |> String.to_integer()
data_dir = System.get_env("DATA_DIR", "data")
kem_dir = System.get_env("KEM_DIR", "priv/kem.key")
falcon_dir = System.get_env("FALCON_DIR", "priv/falcon.key")
key_dir = System.get_env("KEY_DIR", "priv/secret.key")
role = System.get_env("ROLE", "worker")

# Node setup
config :ipnworker, :history, true
# Cluster API (Remote control)
config :ipnworker, :remote, true

# Folders setup
config :ipnworker, :data_dir, data_dir

# Folder cert
config :ipnworker, :kem_dir, kem_dir
config :ipnworker, :falcon_dir, falcon_dir
config :ipnworker, :key_dir, key_dir

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

# Blockchain setup
config :ipnworker, :name, "IPPAN"
config :ipnworker, :token, System.get_env("NATIVE_TOKEN", "IPN")
config :ipnworker, :message_max_size, 8192
config :ipnworker, :version, 0
config :ipnworker, :block_max_size, 10_485_760
config :ipnworker, :block_data_max_size, 10_000_000
config :ipnworker, :block_interval, :timer.seconds(5)
config :ipnworker, :block_extension, "blo"
config :ipnworker, :decode_extension, "dec"
config :ipnworker, :note_max_size, 255
config :ipnworker, :max_tx_amount, 1_000_000_000_000_000
config :ipnworker, :timeout_refund, 75_000
config :ipnworker, :message_timeout, :timer.seconds(5)
config :ipnworker, :max_validators, 20_000
config :ipnworker, :max_tokens, 1_000

# P2P client
config :ipnworker, :p2p_client, [
  :binary,
  active: false,
  reuseaddr: true,
  packet: 2,
  packet_size: 64_000
]

config :ipnworker, json: Jason
config :blake3, rayon: true

import_config "options.exs"
