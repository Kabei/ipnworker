defmodule Download do
  @doc """
  subj.

  Returns:

  * `:ok` if everything were ok.
  * `{ :error, :file_size_is_too_big }` if file size exceeds `max_file_size`
  * `{ :error, :download_failure }` if host isn't reachable
  * `{ :error, :eexist }` if file exists already

  Options:

    * `max_file_size` - max available file size for downloading (in bytes). Default is `1024 * 1024 * 1000` (1GB)
    * `path` - absolute file path for the saved file. Default is `pwd <> requested file name`

  ## Examples

      iex> Download.from("http://speedtest.ftp.otenet.gr/files/test100k.db")
      { :ok, "/absolute/path/to/test_100k.db" }

      iex> Download.from("http://speedtest.ftp.otenet.gr/files/test100k.db", [max_file_size: 99 * 1000])
      { :error, :file_size_is_too_big }

      iex> Download.from("http://speedtest.ftp.otenet.gr/files/test100k.db", [path: "/custom/absolute/file/path.db"])
      { :ok, "/custom/absolute/file/path.db" }

  """
  require Logger
  # 1 GB
  @max_file_size 1024 * 1024 * 1000
  @timeout 60_000
  @retry 10
  @module __MODULE__

  def await(url, path, retry \\ @retry, max_file_size \\ @max_file_size, timeout \\ @timeout) do
    File.rm(path)

    Task.async(fn ->
      try_from(url, path, retry, max_file_size, timeout)
    end)
    |> Task.await(timeout)
  end

  defp try_from(_url, _path, 0, _max_file_size, _timeout) do
    {:error, :many_retry}
  end

  defp try_from(
         url,
         path,
         retry,
         max_file_size,
         timeout
       ) do
    try do
      with {:ok, file} <- create_file(path),
           {:ok, response_parsing_pid} <- create_process(file, path, max_file_size, timeout),
           {:ok, _pid} <- start_download(url, response_parsing_pid, path),
           :ok <- wait_for_download() do
        :ok
      else
        {:error, :file_size_is_too_big} ->
          {:error, :file_size_is_too_big}

        _ ->
          Process.sleep(50)
          try_from(url, path, retry - 1, max_file_size, timeout)
      end
    rescue
      err ->
        Logger.warning(Exception.format(:error, err, __STACKTRACE__))
        Process.sleep(200)
        try_from(url, path, retry, max_file_size, timeout)
    end
  end

  defp create_file(path), do: File.open(path, [:write, :exclusive])

  defp create_process(file, path, max_file_size, timeout) do
    opts = %{
      file: file,
      controlling_pid: self(),
      path: path,
      max_file_size: max_file_size,
      downloaded_content_length: 0,
      timeout: timeout
    }

    {:ok, spawn_link(@module, :do_download, [opts])}
  end

  defp start_download(url, response_parsing_pid, path) do
    request = HTTPoison.get(url, %{}, stream_to: response_parsing_pid, hackney: [:insecure])

    case request do
      {:error, _reason} ->
        File.rm!(path)

      _ ->
        nil
    end

    request
  end

  defp wait_for_download do
    receive do
      reason -> reason
    end
  end

  require Logger
  alias HTTPoison.{AsyncHeaders, AsyncStatus, AsyncChunk, AsyncEnd}
  require Logger
  @doc false
  def do_download(opts) do
    receive do
      response_chunk ->
        handle_async_response_chunk(response_chunk, opts)
    after
      opts.timeout -> {:error, :timeout}
    end
  end

  defp handle_async_response_chunk(%AsyncStatus{code: 200}, opts), do: do_download(opts)

  defp handle_async_response_chunk(%AsyncStatus{code: status_code}, opts) do
    finish_download({:error, :unexpected_status_code, status_code}, opts)
  end

  defp handle_async_response_chunk(%AsyncHeaders{headers: headers}, opts) do
    content_length_header =
      Enum.find(headers, fn {header_name, _value} ->
        header_name == "Content-Length"
      end)

    do_handle_content_length(content_length_header, opts)
  end

  defp handle_async_response_chunk(%AsyncChunk{chunk: data}, opts) do
    downloaded_content_length = opts.downloaded_content_length + byte_size(data)

    if downloaded_content_length < opts.max_file_size do
      IO.binwrite(opts.file, data)

      opts_with_content_length_increased =
        Map.put(opts, :downloaded_content_length, downloaded_content_length)

      do_download(opts_with_content_length_increased)
    else
      finish_download({:error, :file_size_is_too_big}, opts)
    end
  end

  defp handle_async_response_chunk(%AsyncEnd{}, opts), do: finish_download(:ok, opts)

  # Uncomment one line below if you are prefer to test not "Content-Length" header response, but a real file size
  # defp do_handle_content_length(_, opts), do: do_download(opts)
  defp do_handle_content_length({"Content-Length", content_length}, opts) do
    if :erlang.binary_to_integer(content_length) > opts.max_file_size do
      finish_download({:error, :file_size_is_too_big}, opts)
    else
      do_download(opts)
    end
  end

  defp do_handle_content_length(nil, opts), do: do_download(opts)

  defp finish_download(reason, opts) do
    File.close(opts.file)

    if reason != :ok do
      File.rm!(opts.path)
    end

    send(opts.controlling_pid, reason)
  end
end
