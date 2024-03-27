defmodule Ipnworker.FileRoutes do
  use Plug.Router

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  plug(:match)
  plug(:dispatch)

  @app Mix.Project.config()[:app]
  @block_extension Application.compile_env(@app, :block_extension)
  @decode_extension Application.compile_env(@app, :decode_extension)
  @snap_extension Application.compile_env(:ipnworker, :snap_extension)

  alias Ippan.{Block, ClusterNodes}

  get "/block/:vid/:height" do
    base_dir = :persistent_term.get(:block_dir)
    filename = "#{vid}.#{height}.#{@block_extension}"
    block_path = Path.join([base_dir, filename])

    if File.exists?(block_path) do
      conn
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      miner = :persistent_term.get(:miner)
      node = ClusterNodes.info(miner)
      url = Block.cluster_block_url(node.hostname, vid, height)

      case DownloadTask.start(url, block_path) do
        :ok ->
          conn
          |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
          |> put_resp_content_type("application/octet-stream")
          |> send_file(200, block_path)

        _e ->
          send_resp(conn, 404, "")
      end
    end
  end

  get "/decode/:vid/:height" do
    base_dir = :persistent_term.get(:decode_dir)
    filename = "#{vid}.#{height}.#{@decode_extension}"
    block_path = Path.join([base_dir, filename])

    if File.exists?(block_path) do
      conn
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, block_path)
    else
      miner = :persistent_term.get(:miner)
      node = ClusterNodes.info(miner)
      url = Block.cluster_decode_url(node.hostname, vid, height)

      case DownloadTask.start(url, block_path) do
        :ok ->
          conn
          |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
          |> put_resp_content_type("application/octet-stream")
          |> send_file(200, block_path)

        _e ->
          send_resp(conn, 404, "")
      end
    end
  end

  get "/save/:round_id" do
    save_dir = :persistent_term.get(:save_dir)
    filename = "#{round_id}.#{@snap_extension}"
    filepath = Path.join([save_dir, filename])

    if File.exists?(filepath) do
      conn
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, filepath)
    else
      miner = :persistent_term.get(:miner)
      node = ClusterNodes.info(miner)
      port = Application.get_env(@app, :x_http_port)
      url = "http://#{node.hostname}:#{port}/v1/dl/save/#{round_id}"

      case DownloadTask.start(url, filepath) do
        :ok ->
          conn
          |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
          |> put_resp_content_type("application/octet-stream")
          |> send_file(200, filepath)

        _e ->
          send_resp(conn, 404, "")
      end
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
