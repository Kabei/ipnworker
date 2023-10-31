defmodule Ipnworker.Router do
  use Plug.Router
  alias Ippan.{ClusterNodes, TxHandler, Validator}
  require Ippan.{Validator, TxHandler}
  require Sqlite
  require Logger
  import Ippan.Utils, only: [json: 1]

  @app Mix.Project.config()[:app]
  @json Application.compile_env(@app, :json)
  @max_size Application.compile_env(@app, :message_max_size)

  plug(:match)
  plug(:dispatch)

  post "/v1/call" do
    try do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

      case get_req_header(conn, "auth") do
        [sig64] ->
          hash = Blake3.hash(body)
          signature = Fast64.decode64(sig64)
          size = byte_size(body) + byte_size(signature)
          [type, nonce, from | args] = @json.decode!(body)
          from_nonce = {from, nonce}

          case :ets.insert_new(:hash, {from_nonce, nil}) do
            true ->
              %{id: vid} = validator = :persistent_term.get(:validator)

              handle_result =
                [deferred, msg, _return] =
                try do
                  TxHandler.decode!()
                rescue
                  e ->
                    :ets.delete(:hash, from_nonce)
                    reraise e, __STACKTRACE__
                end

              dtx_key =
                if deferred do
                  [hash, type, key | _rest] = msg

                  case :ets.insert_new(:dhash, {{type, key}, hash}) do
                    true ->
                      {type, key}

                    false ->
                      :ets.delete(:hash, from_nonce)
                      raise IppanError, "Deferred transaction already exists"
                  end
                end

              miner_id = :persistent_term.get(:miner)

              case ClusterNodes.call(miner_id, "new_msg", handle_result) do
                {:ok, %{"height" => height}} ->
                  # Update nonce
                  cache_nonce_tx = DetsPlux.tx(:nonce, :cache_nonce)
                  DetsPlux.put(cache_nonce_tx, from, nonce)

                  json(%{
                    "hash" => Base.encode16(hash, case: :lower),
                    "height" => height
                  })

                {:error, message} ->
                  :ets.delete(:hash, from_nonce)

                  if dtx_key do
                    :ets.delete(:dhash, dtx_key)
                  end

                  case message do
                    message when is_binary(message) ->
                      send_resp(conn, 400, message)

                    _ ->
                      send_resp(conn, 503, "")
                  end
              end

            false ->
              send_resp(conn, 400, "Transaction already exists")
          end

        _ ->
          send_resp(conn, 400, "Signature missing")
      end
    rescue
      e in IppanError ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        send_resp(conn, 400, e.message)

      e in IppanRedirectError ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        db_ref = :persistent_term.get(:main_conn)

        %{hostname: hostname} =
          Validator.get(String.to_integer(e.message))

        url = "https://#{hostname}#{conn.request_path}"

        conn
        |> put_resp_header("location", url)
        |> send_resp(302, "")

      e in [FunctionClauseError, ArgumentError] ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        send_resp(conn, 400, "Invalid arguments")

      e ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        send_resp(conn, 400, "Invalid operation")
    end
  end

  forward("/v1/dl", to: Ipnworker.FileRoutes)
  forward("/v1/round", to: Ipnworker.RoundRoutes)
  forward("/v1/block", to: Ipnworker.BlockRoutes)
  forward("/v1/txs", to: Ipnworker.TxRoutes)
  forward("/v1/payment", to: Ipnworker.PaymentsRoutes)
  forward("/v1/validator", to: Ipnworker.ValidatorRoutes)
  forward("/v1/token", to: Ipnworker.TokenRoutes)
  forward("/v1/jackpot", to: Ipnworker.JackpotRoutes)
  forward("/v1/domain", to: Ipnworker.DomainRoutes)
  forward("/v1/dns", to: Ipnworker.DnsRoutes)
  forward("/v1/network", to: Ipnworker.NetworkRoutes)
  forward("/v1/account", to: Ipnworker.AccountRoutes)
  forward("/v1/event", to: Ipnworker.EventRoutes)
  # forward "/v1/snap", to: Ipnworker.SnapRoutes

  if Application.compile_env(@app, :remote) do
    forward("/v1/cluster", to: Ipnworker.ClusterRoutes)
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
