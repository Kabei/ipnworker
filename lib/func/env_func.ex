defmodule Ippan.Func.Env do
  def set(%{id: account_id}, name, value) do
    bin = :erlang.term_to_binary(value)

    cond do
      byte_size(name) >= 256 ->
        raise IppanError, "Name is too long"

      byte_size(bin) > 4096 ->
        raise IppanError, "Value is too long"

      :persistent_term.get(:owner) != account_id ->
        raise IppanError, "Unauthorized"

      true ->
        :ok
    end
  end

  def delete(%{id: account_id}, name) do
    cond do
      byte_size(name) >= 256 ->
        raise IppanError, "Name is too long"

      :persistent_term.get(:owner) != account_id ->
        raise IppanError, "Unauthorized"

      true ->
        :ok
    end
  end
end
