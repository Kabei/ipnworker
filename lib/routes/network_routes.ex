defmodule Ipnworker.NetworkRoutes do
  use Plug.Router
  require Ippan.{Block, Round, Token, Validator}
  alias Ippan.{Block, Round, Token, Validator, Utils}
  require Sqlite
  import Ippan.Utils, only: [json: 1]

  @app Mix.Project.config()[:app]
  @token Application.compile_env(@app, :token)
  @name Application.compile_env(@app, :name)
  @jackpot "jackpot"

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
    "max_tx_amount" => Application.compile_env(@app, :max_tx_amount),
    "message_max_size" => Application.compile_env(@app, :message_max_size),
    "message_timeout" => Application.compile_env(@app, :message_timeout),
    "max_validators" => Application.compile_env(@app, :max_validators),
    "max_tokens" => Application.compile_env(@app, :max_tokens),
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
    {id, hash} = Round.last()
    blocks = Block.total()
    validators = Validator.total()
    tokens = Token.total()
    dets = DetsPlux.get(:wallet)
    accounts = DetsPlux.info(dets, nil, :size)
    supply = TokenSupply.new(@token)
    jackpot = TokenSupply.new(@jackpot)

    %{
      "accounts" => accounts,
      "blocks" => blocks,
      "env" => EnvStore.all(db_ref),
      "hash" => Utils.encode16(hash),
      "id" => id,
      "jackpot" => TokenSupply.get(jackpot),
      "name" => @name,
      "supply" => TokenSupply.get(supply),
      "token" => @token,
      "tokens" => tokens,
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
