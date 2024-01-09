defmodule SSE do
  require Logger
  alias Phoenix.PubSub
  import Plug.Conn, only: [chunk: 2, halt: 1, put_resp_header: 3, send_chunked: 2]
  @timeout 120_000

  def stream(conn, pubsub, topic, opts) do
    timeout = Keyword.get(opts, :timeout, @timeout)
    once = Keyword.get(opts, :once, true)

    conn =
      conn
      |> put_resp_header("Cache-Control", "no-cache")
      |> put_resp_header("Content-Type", "text/event-stream")
      |> put_resp_header("Connection", "keep-alive")
      |> send_chunked(200)

    PubSub.subscribe(pubsub, topic)
    Process.flag(:trap_exit, true)

    {_, adapter} = conn.adapter
    socket = adapter.socket.socket
    transport = adapter.socket.transport_module

    transport.controlling_process(socket, self())
    transport.setopts(socket, [{:active, true}])

    loop(conn, pubsub, topic, once, timeout)
  end

  def shutdown(conn, pubsub, topic) do
    PubSub.unsubscribe(pubsub, topic)
    halt(conn)
  end

  @ping_time 55_000
  defp loop(conn, pubsub, topic, once, timeout) do
    tRef =
      if timeout > @ping_time do
        {:ok, tref} = :timer.send_after(@ping_time, :ping)
        tref
      end

    receive do
      :ping ->
        :timer.cancel(tRef)

        conn
        |> chunk("event:message\ndata:\n\n")
        |> case do
          {:ok, conn} ->
            loop(conn, pubsub, topic, once, timeout)

          _error ->
            shutdown(conn, pubsub, topic)
        end

      message when not is_tuple(message) and not is_atom(message) ->
        Logger.debug(inspect(message))
        :timer.cancel(tRef)

        conn
        |> chunk("event:message\ndata:#{Jason.encode!(message)}\n\n")
        |> case do
          {:ok, conn} ->
            case once do
              true ->
                send_close(conn, pubsub, topic, :shutdown)

              _ ->
                loop(conn, pubsub, topic, once, timeout)
            end

          _error ->
            shutdown(conn, pubsub, topic)
        end

      {:halt, message} ->
        Logger.debug(message)
        :timer.cancel(tRef)

        conn
        |> chunk("event:message\ndata:#{Jason.encode!(message)}\n\n")
        |> case do
          {:ok, conn} ->
            send_close(conn, pubsub, topic, :end)

          _error ->
            shutdown(conn, pubsub, topic)
        end

      {:tcp_closed, _socket} ->
        Logger.debug("TCP closed")
        :timer.cancel(tRef)
        shutdown(conn, pubsub, topic)

      {:tcp_error, _socket, _reason} ->
        :timer.cancel(tRef)
        Logger.debug("TCP error")
        shutdown(conn, pubsub, topic)

      {:plug_conn, msg} ->
        Logger.debug("plug_conn #{inspect(msg)}")
        :timer.cancel(tRef)
        loop(conn, pubsub, topic, once, timeout)

      {:EXIT, _from, _reason} ->
        :timer.cancel(tRef)
        PubSub.unsubscribe(pubsub, topic)
        Process.exit(conn.owner, :normal)

      {:DOWN, _reference, _process, _pid, _type} ->
        :timer.cancel(tRef)
        PubSub.unsubscribe(pubsub, topic)

      other ->
        :timer.cancel(tRef)
        Logger.debug("Other: #{inspect(other)}")
        send_close(conn, pubsub, topic, :shutdown)
    after
      timeout ->
        :timer.cancel(tRef)
        send_close(conn, pubsub, topic, :timeout)
    end
  end

  defp send_close(conn, pubsub, topic, reason) do
    Logger.debug("close")
    PubSub.unsubscribe(pubsub, topic)

    conn
    |> chunk("event:close\ndata:#{reason}\n\n")
    |> case do
      {:ok, conn} ->
        halt(conn)

      _error ->
        halt(conn)
    end
  end
end
