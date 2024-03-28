defmodule Ipnworker.NetworkRoutes do
  use Plug.Router
  require Ippan.{Block, Round, Token, Validator}
  alias Ippan.{Token, Validator, Utils}
  require Sqlite
  import Ippan.Utils, only: [json: 1]

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @name Application.compile_env(@app, :name)

  @options %{
    "app_version" => Ipnworker.MixProject.version(),
    "block_data_max_size" => Application.compile_env(@app, :block_data_max_size),
    "block_extension" => Application.compile_env(@app, :block_extension),
    "reserve" => Application.compile_env(@app, :reserve),
    "round_timeout" => Application.compile_env(@app, :round_timeout),
    "block_max_size" => Application.compile_env(@app, :block_max_size),
    "blockchain_version" => Application.compile_env(@app, :version),
    "decode_extension" => Application.compile_env(@app, :decode_extension),
    "note_max_size" => Application.compile_env(@app, :note_max_size),
    "maintenance" => Application.compile_env(@app, :maintenance),
    "max_tx_amount" => Application.compile_env(@app, :max_tx_amount),
    "message_max_size" => Application.compile_env(@app, :message_max_size),
    "message_timeout" => Application.compile_env(@app, :message_timeout),
    "max_validators" => Application.compile_env(@app, :max_validators),
    "max_services" => Application.compile_env(@app, :max_services, 0),
    "max_tokens" => Application.compile_env(@app, :max_tokens, 0),
    "name" => @name,
    "timeout_refund" => Application.compile_env(@app, :timeout_refund),
    "token" => @token
  }

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  get "/status" do
    db_ref = :persistent_term.get(:main_conn)
    wallet = DetsPlux.get(:wallet)
    stats = Stats.cache()
    supply = TokenSupply.cache(@token)

    id = Stats.get(stats, "last_round", 0)
    hash = Stats.get(stats, "last_hash", nil)
    blocks = Stats.get(stats, "blocks")
    txs = Stats.get(stats, "txs")
    validators = Validator.total()
    tokens = Token.total()
    accounts = DetsPlux.info(wallet, :size)
    jackpot = TokenSupply.cache("jackpot")

    %{
      "accounts" => accounts,
      "blocks" => blocks,
      "env" => EnvStore.all(db_ref),
      "hash" => Utils.encode16(hash),
      "id" => id,
      "jackpot" => TokenSupply.get(jackpot),
      "snapshot" => Snapshot.last(stats),
      "name" => @name,
      "services" => Stats.get(stats, "services"),
      "supply" => TokenSupply.get(supply),
      "token" => @token,
      "tokens" => tokens,
      "txs" => txs,
      "validators" => validators
    }
    |> json()
  end

  get "/options" do
    @options
    |> json()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
