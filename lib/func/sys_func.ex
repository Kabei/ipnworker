defmodule Ippan.Func.Sys do
  def upgrade(%{id: account_id}, %{"git" => _git}, _target) do
    cond do
      EnvStore.owner() != account_id ->
        raise IppanError, "Unauthorized "

      true ->
        :ok
    end
  end
end
