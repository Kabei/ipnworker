defmodule Ipnworker.Router do
  use Plug.Router
  alias Ippan.Block
  alias Ippan.Validator
  alias Ippan.ClusterNode
  alias Ippan.TxHandler
  require SqliteStore
  require Logger

  @json Application.compile_env(:ipnworker, :json)
  @max_size Application.compile_env(:ipnworker, :message_max_size)
  @block_extension Application.compile_env(:ipnworker, :block_extension)

  plug(:match)
  plug(:dispatch)

  post "/v1/call" do
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

              handle_result =
                [deferred, msg] = TxHandler.valid!(hash, body, sig, size, vid)

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
              :ets.insert(:hash, {hash, height})

              case ClusterNode.call(miner_id, "new_msg", handle_result) do
                {:ok, %{"height" => height}} ->
                  json(conn, %{
                    "hash" => Base.encode16(hash, case: :lower),
                    "height" => height
                  })

                {:error, :timeout} ->
                  :ets.delete(:hash, hash)
                  :ets.delete(:dhash, dtx_key)
                  send_resp(conn, 503, "Service unavailable")

                {:error, message} ->
                  :ets.delete(:hash, hash)
                  :ets.delete(:dhash, dtx_key)
                  send_resp(conn, 400, message)
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

  get "/v1/download/block/decoded/:vid/:height" do
    decode_dir = :persistent_term.get(:decode_dir)
    block_path = Path.join([decode_dir, "#{vid}.#{height}.#{@block_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      send_resp(conn, 404, "")
    end
  end

  get "/v1/download/block/:vid/:height" do
    data_dir = :persistent_term.get(:block_dir)
    block_path = Path.join([data_dir, "#{vid}.#{height}.#{@block_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      if vid == :persistent_term.get(:vid) do
        miner = :persistent_term.get(:miner)
        node = ClusterNode.info(miner)
        url = Block.cluster_block_url(node.hostname, vid, height)

        case Download.from(url, block_path) do
          :ok ->
            conn
            |> put_resp_content_type("application/octet-stream")
            |> send_file(200, block_path)

          _ ->
            send_resp(conn, 404, "")
        end
      else
        send_resp(conn, 404, "")
      end
    end
  end

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
