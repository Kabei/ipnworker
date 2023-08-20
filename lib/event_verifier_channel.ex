defmodule EventVerifierChannel do
  alias Phoenix.PubSub
  @pubsub_server :workers

  def handle_msg("msg", %{"hash" => hash, "status" => status}) do
    PubSub.local_broadcast(@pubsub_server, "tx:#{hash}", status)
  end

  def handle_msg("new_round", _data) do
    :ok
  end
end
