defmodule Ipnworker.NetworkRoutes do
  use Plug.Router
  require Ippan.{Block, Round, Token, Validator}
  alias Ippan.{Block, Round, Token, Validator, Utils}
  require Sqlite
  import Ippan.Utils, only: [json: 1]

  @app :ipnworker
  @token Application.compile_env(@app, :token)

  @options %{
    "app_version" => Ipnworker.MixProject.version(),
    "block_data_max_size" => Application.compile_env(@app, :block_data_max_size),
    "block_extension" => Application.compile_env(@app, :block_extension),
    "block_interval" => Application.compile_env(@app, :block_interval),
    "block_max_size" => Application.compile_env(@app, :block_max_size),
    "blockchain_version" => Application.compile_env(@app, :version),
    "decode_extension" => Application.compile_env(@app, :decode_extension),
    "note_max_size" => Application.compile_env(@app, :note_max_size),
    "max_tx_amount" => Application.compile_env(@app, :max_tx_amount),
    "message_max_size" => Application.compile_env(@app, :message_max_size),
    "message_timeout" => Application.compile_env(@app, :message_timeout),
    "max_validators" => Application.compile_env(@app, :max_validators),
    "max_tokens" => Application.compile_env(@app, :max_tokens),
    "name" => Application.compile_env(@app, :name),
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
    block_id = Block.last_id()
    validators = Validator.total()
    tokens = Token.total()
    dets = DetsPlux.get(:wallet)
    accounts = DetsPlux.info(dets, nil, :size)
    dets2 = DetsPlux.get(:stats)
    supply = DetsPlux.get(dets2, DetsPlux.tuple(@token, "supply"), 0)

    %{
      "accounts" => accounts,
      "block_id" => block_id,
      "env" => EnvStore.all(db_ref),
      "hash" => Utils.encode16(hash),
      "id" => id,
      "supply" => supply,
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
