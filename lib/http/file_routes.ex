defmodule Ipnworker.FileRoutes do
  use Plug.Router

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  @block_extension Application.compile_env(:ipnworker, :block_extension)
  @decode_extension Application.compile_env(:ipnworker, :decode_extension)
  alias Ippan.{Block, ClusterNodes}

  get "/block/:vid/:height" do
    base_dir = :persistent_term.get(:decode_dir)
    block_path = Path.join([base_dir, "#{vid}.#{height}.#{@block_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      send_resp(conn, 404, "")
    end
  end

  get "/decode/:vid/:height" do
    base_dir = :persistent_term.get(:block_dir)
    block_path = Path.join([base_dir, "#{vid}.#{height}.#{@decode_extension}"])

    if File.exists?(block_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      if vid == :persistent_term.get(:vid) |> to_string do
        miner = :persistent_term.get(:miner)
        node = ClusterNodes.info(miner)
        url = Block.cluster_block_url(node.hostname, vid, height)

        case Download.await(url, block_path) do
          :ok ->
            conn
            |> put_resp_content_type("application/octet-stream")
            |> send_file(200, block_path)

          _e ->
            send_resp(conn, 404, "")
        end
      else
        send_resp(conn, 404, "")
      end
    end
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
