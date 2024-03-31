defmodule Ippan.Func.Sys do
  @dev_mode Mix.env() == :dev

  if @dev_mode do
    def upgrade(%{id: account_id}, %{"reset" => "reset_data"}, _target) do
      if EnvStore.owner() != account_id, do: raise(IppanError, "Unauthorized")
    end
  end

  def upgrade(%{id: account_id}, %{"git" => _git}, _target) do
    cond do
      EnvStore.owner() != account_id ->
        raise IppanError, "Unauthorized"

      true ->
        :ok
    end
  end
end
