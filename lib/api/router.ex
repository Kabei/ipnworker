defmodule Ipnworker.Router do
  use Plug.Router
  alias Ippan.Validator
  alias Ippan.ClusterNode
  alias Ippan.EventHandler
  # alias Phoenix.PubSub
  require SqliteStore
  require Logger

  @json Application.compile_env(:ipnworker, :json)
  @max_size Application.compile_env(:ipnworker, :message_max_size)
  @block_extension Application.compile_env(:ipnworker, :block_extension)

  plug(:match)
  plug(:dispatch)

  post "/v1/call" do
    IO.inspect(conn)

    try do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: @max_size)

      case get_req_header(conn, "auth") do
        [sig] ->
          hash = Blake3.hash(body)

          case :ets.member(:hash, hash) do
            false ->
              vid = :persistent_term.get(:vid)
              height = :persistent_term.get(:height)
              sig = Fast64.decode64(sig)
              size = byte_size(body) + byte_size(sig)
              {msg, msg_sig, deferred} = EventHandler.valid!(hash, body, sig, size, vid)

              dtx_key =
                if deferred do
                  {hash, timestamp, key, type, _from, _wallet_validator, _args, _msg_sig, _size} =
                    msg

                  case :ets.insert_new(:dmsg, {{type, key}, hash, timestamp, height}) do
                    true ->
                      {type, key}

                    false ->
                      raise IppanError, "Invalid deferred transaction"
                  end
                end

              miner_id = :persistent_term.get(:miner)
              inserted = :ets.insert_new(:hash, {hash, height})

              cond do
                inserted ->
                  case ClusterNode.call(miner_id, "new_msg", [msg, msg_sig]) do
                    %{"height" => height} ->
                      json(conn, %{
                        "hash" => Base.encode16(hash, case: :lower),
                        "height" => height
                      })

                    %{"error" => message} ->
                      :ets.delete(:hash, hash)
                      :ets.delete(:dmsg, dtx_key)
                      send_resp(conn, 400, message)

                    {:error, _} ->
                      :ets.delete(:hash, hash)
                      :ets.delete(:dmsg, dtx_key)
                      send_resp(conn, 503, "Service unavailable")
                  end

                deferred ->
                  :ets.delete(:dmsg, dtx_key)
              end

            true ->
              send_resp(conn, 400, "Already exists")
          end

        _ ->
          send_resp(conn, 400, "Signature missing")
      end
    rescue
      e in IppanError ->
        send_resp(conn, 400, e.message)

      e in IppanRedirectError ->
        conn = :persistent_term.get(:asset_conn)
        stmts = :persistent_term.get(:asset_stmt)

        %{hostname: hostname} =
          SqliteStore.lookup_map(
            :validator,
            conn,
            stmts,
            "get_validator",
            String.to_integer(e.message),
            Validator
          )

        url = "https://#{hostname}#{conn.request_path}"

        conn
        |> put_resp_header("location", url)
        |> send_resp(302, "")

      e ->
        Logger.debug(Exception.format(:error, e, __STACKTRACE__))
        send_resp(conn, 400, "Invalid operation")
    end
  end

  get "/v1/download/block/:vid/:height" do
    data_dir = Application.get_env(:ipnworker, :block_dir)
    block_path = Path.join([data_dir, "#{vid}.#{height}.#{@block_extension}"])

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
    block_path = Path.join([decode_dir, "#{vid}.#{height}.#{@block_extension}"])

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
