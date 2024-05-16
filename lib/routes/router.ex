defmodule Ipnworker.Router do
  use Plug.Router
  alias Ippan.Funcs
  alias Ippan.{ClusterNodes, TxHandler, Validator}
  require Logger
  import Ippan.Utils, only: [json: 1]

  @app Mix.Project.config()[:app]
  @json Application.compile_env(@app, :json)
  @max_size Application.compile_env(@app, :message_max_size)
  # Enable
  @api Application.compile_env(@app, :api, true)
  @call Application.compile_env(@app, :call, true)
  @admin Application.compile_env(@app, :admin, false)

  plug(:match)
  plug(:dispatch)

  if @call do
    post "/v1/call" do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

      if :persistent_term.get(:status) == :synced do
        case get_req_header(conn, "auth") do
          [sig64] ->
            try do
              db_ref = :persistent_term.get(:main_conn)
              hash = Blake3.hash(body)
              signature = Fast64.decode64(sig64)
              size = byte_size(body) + byte_size(signature)
              [type_id, nonce, from | args] = @json.decode!(body)
              vid = :persistent_term.get(:vid)

              validator =
                Validator.get(db_ref, vid) ||
                  raise IppanError, "Node is not available yet"

              type = Funcs.lookup(type_id)
              ets = :ets.whereis(:hash)

              map = %{
                args: args,
                hash: hash,
                ets: ets,
                refs: %{
                  dets: :persistent_term.get(:dets),
                  tx: :persistent_term.get({:dets, :cache})
                },
                type: type,
                size: size,
                validator: validator,
                sig: signature
              }

              {key, result} = TxHandler.valid!(map)
              miner_id = :persistent_term.get(:miner)

              case ClusterNodes.call(miner_id, "tx", result) do
                {:ok, %{"index" => index}} ->
                  :ets.insert(ets, {key, result})
                  nonce_dets = DetsPlux.get(:nonce)
                  nonce_tx = DetsPlux.tx(nonce_dets, :cache_nonce)
                  DetsPlux.put(nonce_tx, from, nonce)

                  json(%{
                    "hash" => Base.encode16(hash, case: :lower),
                    "index" => index
                  })

                {:error, message} ->
                  case message do
                    message when is_binary(message) ->
                      send_resp(conn, 400, message)

                    _ ->
                      send_resp(conn, 503, "")
                  end
              end
            rescue
              e in [IppanError, MatchError, IppanHighError, ArgumentError] ->
                Logger.debug(Exception.format(:error, e, __STACKTRACE__))
                send_resp(conn, 400, e.message)

              e in IppanRedirectError ->
                Logger.debug(Exception.format(:error, e, __STACKTRACE__))
                db_ref = :persistent_term.get(:main_conn)

                %{hostname: hostname} =
                  Validator.get(db_ref, e.message)

                url = "https://#{hostname}#{conn.request_path}"

                conn
                |> put_resp_header("location", url)
                |> send_resp(302, "")

              e in FunctionClauseError ->
                Logger.debug(Exception.format(:error, e, __STACKTRACE__))
                send_resp(conn, 400, "Invalid arguments")

              e ->
                Logger.debug(Exception.format(:error, e, __STACKTRACE__))
                send_resp(conn, 400, "Invalid operation")
            end

          _ ->
            send_resp(conn, 400, "Signature missing")
        end
      else
        send_resp(conn, 503, "Node is synchronizing")
      end
    end
  end

  get "/v1/info" do
    info = Ippan.Ecto.Validator.me()
    hash = "\"#{:erlang.phash2(info)}\""

    case get_req_header(conn, "etag") do
      [etag] ->
        if hash == etag do
          send_resp(conn, 304, "")
        else
          conn
          |> put_resp_header("Etag", hash)
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(info))
        end

      _ ->
        info = Ippan.Ecto.Validator.me()

        conn
        |> put_resp_header("Etag", hash)
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(info))
    end
  end

  if @api do
    forward("/v1/dl", to: Ipnworker.FileRoutes)
    forward("/v1/round", to: Ipnworker.RoundRoutes)
    forward("/v1/block", to: Ipnworker.BlockRoutes)
    forward("/v1/txs", to: Ipnworker.TxRoutes)
    forward("/v1/payment", to: Ipnworker.PaymentsRoutes)
    forward("/v1/validator", to: Ipnworker.ValidatorRoutes)
    forward("/v1/token", to: Ipnworker.TokenRoutes)
    forward("/v1/jackpot", to: Ipnworker.JackpotRoutes)
    # forward("/v1/domain", to: Ipnworker.DomainRoutes)
    # forward("/v1/dns", to: Ipnworker.DnsRoutes)
    forward("/v1/network", to: Ipnworker.NetworkRoutes)
    forward("/v1/account", to: Ipnworker.AccountRoutes)
    forward("/v1/event", to: Ipnworker.EventRoutes)
    forward("/v1/service", to: Ipnworker.ServiceRoutes)
    forward("/v1/subpay", to: Ipnworker.SubPayRoutes)
    # forward "/v1/cluster", to: Ipnworker.NodeRoutes
    # forward "/v1/snap", to: Ipnworker.SnapRoutes
  end

  if @admin do
    forward("/v1/cluster", to: Ipnworker.ClusterRoutes)
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
