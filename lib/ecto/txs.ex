defmodule Ippan.Ecto.Tx do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @primary_key false
  @schema_prefix "history"
  schema "txs" do
    field(:block_id, :integer)
    field(:hash, :binary)
    field(:type, :integer)
    field(:from, :binary)
    field(:nonce, :integer)
    field(:size, :integer)
    field(:args, :string)
  end

  @select ~w(block_id hash type from nonce size args)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(block_id, hash16) do
    hash = Base.decode16!(hash16, case: :mixed)

    from(tx in Tx, where: tx.block_id == ^block_id and tx.hash == ^hash, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def all(params) do
    from(Tx)
    |> filter_offset(params)
    |> filter_limit(params)
    |> filter_block(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_select(query) do
    select(query, [tx], map(tx, @select))
  end

  defp filter_block(query, %{"block" => id}) do
    where(query, [tx], tx.block_id <= ^id)
  end

  defp filter_block(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [tx], asc: tx.block_id)
  defp sort(query, _), do: order_by(query, [tx], desc: tx.block_id)

  defp fun(x = %{hash: hash}) do
    %{x | hash: Utils.encode16(hash)}
  end
end