defmodule Ipnworker.Router do
  use Plug.Router
  alias Ippan.CommandHandler
  alias Phoenix.PubSub
  require Logger

  @json Application.compile_env(:ipnworker, :json)
  @max_size Application.compile_env(:ipnworker, :message_max_size)
  @file_extension Application.compile_env(:ipnworker, :block_file_ext)

  plug(:match)
  plug(:dispatch)

  post "/v1/call" do
    try do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

      case get_req_header(conn, "auth") do
        [sig] ->
          hash = Blake3.hash(body)

          case :ets.member(:hash, hash) do
            true ->
              vid = :persistent_term.get(:vid)
              sig = Fast64.decode64(sig)
              size = byte_size(body) + byte_size(sig)
              {msg, deferred} = CommandHandler.valid!(hash, body, sig, size, vid)

              case deferred do
                false ->
                  :ets.insert(:msg, msg)

                _true ->
                  {hash, timestamp, key, type, _from, _wallet_validator, _args, _msg_sig, _size} =
                    msg

                  case :ets.insert_new(:msg, {{type, key}, hash, timestamp}) do
                    true ->
                      :ets.insert(:msg, msg)

                    false ->
                      raise IppanError, "Invalid deferred transaction"
                  end
              end

              timestamp = elem(msg, 1)
              :ets.insert(:hash, {hash, timestamp})

              PubSub.local_broadcast(:cores, "msg", %{data: msg, deferred: deferred})
              json(conn, %{"hash" => Base.encode16(hash, case: :lower)})

            false ->
              send_resp(conn, 400, "Already exists")
          end

        _ ->
          send_resp(conn, 400, "Signature missing")
      end
    rescue
      e in [IppanError] ->
        send_resp(conn, 400, e.message)

      e ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        send_resp(conn, 400, "Invalid operation")
    end
  end

  get "/v1/download/block/:vid/:height" do
    data_dir = Application.get_env(:ipnworker, :block_dir)
    block_path = Path.join([data_dir, "#{vid}.#{height}.#{@file_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      send_resp(conn, 404, "")
    end
  end

  get "/v1/download/block/decoded/:vid/:height" do
    decode_dir = Application.get_env(:ipnworker, :decode_dir)
    block_path = Path.join([decode_dir, "#{vid}.#{height}.#{@file_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      send_resp(conn, 404, "")
    end
  end

  # miner = System.get_env("MINER")

  #     unless is_nil(miner) do
  #       ip_local = String.split(miner, "@") |> List.last()
  #       url = Block.cluster_block_url(ip_local, vid, height)

  #       case Curl.download_block(url, block_path) do
  #         :ok ->
  #           conn
  #           |> put_resp_content_type("application/octet-stream")
  #           |> send_file(200, block_path)

  #         res ->
  #           Logger.debug(inspect(res))
  #           send_resp(conn, 404, "")
  #       end
  #     else
  #       send_resp(conn, 404, "")
  #     end

  match _ do
    send_resp(conn, 404, "")
  end

  # defp handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
  #   send_resp(conn, conn.status, "Something went wrong")
  # end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, @json.encode!(data))
  end
end
