defmodule Ipnworker.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  @json Application.compile_env(:ipnworker, :json)
  @max_size Application.compile_env(:ipnworker, :message_max_size)

  alias Ippan.{ClusterNodes, TxHandler, Validator}
  require Sqlite
  require Validator
  require TxHandler
  require Logger
  import Ippan.Utils, only: [json: 1]

  post "/v1/call" do
    try do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

      case get_req_header(conn, "auth") do
        [sig64] ->
          hash = Blake3.hash(body)

          case :ets.member(:hash, hash) do
            false ->
              # vid = :persistent_term.get(:vid)
              # height = :persistent_term.get(:height)
              signature = Fast64.decode64(sig64)
              size = byte_size(body) + byte_size(signature)
              %{id: vid} = validator = :persistent_term.get(:validator)
              [type, nonce, from | args] = @json.decode!(body)

              handle_result =
                [deferred, msg, _return] = TxHandler.decode!()

              dtx_key =
                if deferred do
                  [hash, type, key | _rest] = msg

                  case :ets.insert_new(:dhash, {{type, key}, hash}) do
                    true ->
                      {type, key}

                    false ->
                      raise IppanError, "Deferred transaction already exists"
                  end
                end

              miner_id = :persistent_term.get(:miner)

              case ClusterNodes.call(miner_id, "new_msg", handle_result) do
                {:ok, %{"height" => height}} ->
                  :ets.insert(:hash, {hash, height})

                  json(%{
                    "hash" => Base.encode16(hash, case: :lower),
                    "height" => height
                  })

                {:error, message} ->
                  :ets.delete(:hash, hash)
                  :ets.delete(:dhash, dtx_key)

                  case message do
                    :timeout ->
                      send_resp(conn, 503, "Service unavailable")

                    :not_exists ->
                      send_resp(conn, 503, "Service unavailable")

                    message ->
                      send_resp(conn, 400, message)
                  end
              end

            true ->
              send_resp(conn, 400, "Transaction already exists")
          end

        _ ->
          send_resp(conn, 400, "Signature missing")
      end
    rescue
      e in IppanError ->
        send_resp(conn, 400, e.message)

      e in IppanRedirectError ->
        db_ref = :persistent_term.get(:main_conn)

        %{hostname: hostname} =
          Validator.get(String.to_integer(e.message))

        url = "https://#{hostname}#{conn.request_path}"

        conn
        |> put_resp_header("location", url)
        |> send_resp(302, "")

      [FunctionClauseError, ArgumentError] ->
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
  forward("/v1/validator", to: Ipnworker.ValidatorRoutes)
  forward("/v1/token", to: Ipnworker.TokenRoutes)
  forward("/v1/jackpot", to: Ipnworker.JackpotRoutes)
  forward("/v1/domain", to: Ipnworker.DomainRoutes)
  forward("/v1/dns", to: Ipnworker.DnsRoutes)
  forward("/v1/network", to: Ipnworker.NetworkRoutes)
  forward("/v1/account", to: Ipnworker.AccountRoutes)
  forward "/v1/event", to: Ipnworker.EventRoutes
  # forward "/v1/snap", to: Ipnworker.SnapRoutes

  match _ do
    send_resp(conn, 404, "")
  end

  # defp handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
  #   send_resp(conn, conn.status, "Something went wrong")
  # end
end