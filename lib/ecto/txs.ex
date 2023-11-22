defmodule Ippan.Ecto.Tx do
  use Ecto.Schema
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3, select: 3, where: 3]
  alias Ippan.Ecto.Block
  alias Ippan.Utils
  alias Ipnworker.Repo
  alias __MODULE__

  @app Mix.Project.config()[:app]
  @json Application.compile_env(@app, :json)

  @craw "application/octet-stream"
  @cjson "application/json"
  @ccbor "application/cbor"

  @primary_key false
  @schema_prefix "history"
  schema "txs" do
    field(:nonce, :integer)
    field(:from, :binary)
    field(:ix, :integer)
    field(:block, :integer)
    field(:hash, :binary)
    field(:type, :integer)
    field(:status, :integer)
    field(:size, :integer)
    field(:ctype, :integer)
    field(:args, :binary)
    field(:signature, :binary)
  end

  @select ~w(from nonce ix block hash type status size ctype args signature)a

  import Ippan.Ecto.Filters, only: [filter_limit: 2, filter_offset: 2]

  def one(from, nonce) do
    from(tx in Tx, where: tx.from == ^from and tx.nonce == ^nonce, limit: 1)
    |> filter_select()
    |> Repo.one()
    |> case do
      nil -> nil
      x -> fun(x)
    end
  end

  def one(vid, height, ix) do
    from(b in Block,
      join: tx in Tx,
      on: tx.block == b.id,
      where:
        b.creator == ^vid and b.height == ^height and
          tx.ix == ^ix,
      limit: 1
    )
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
    |> filter_address(params)
    |> filter_type(params)
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
    where(query, [tx], tx.block == ^id)
  end

  defp filter_block(query, %{"blockEnd" => fin, "blockStart" => start}) do
    where(query, [tx], tx.block >= ^start and tx.block >= ^fin)
  end

  defp filter_block(query, %{"blockEnd" => id}) do
    where(query, [tx], tx.block <= ^id)
  end

  defp filter_block(query, %{"blockStart" => id}) do
    where(query, [tx], tx.block >= ^id)
  end

  defp filter_block(query, _), do: query

  defp filter_address(query, %{"from" => address}) do
    where(query, [tx], tx.from == ^address)
  end

  defp filter_address(query, _), do: query

  defp filter_type(query, %{"type" => type}) do
    where(query, [tx], tx.type == ^type)
  end

  defp filter_type(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [tx], asc: tx.block)
  defp sort(query, _), do: order_by(query, [tx], desc: tx.block)

  defp fun(x = %{args: nil, hash: hash, ctype: ctype, signature: signature}) do
    %{x | ctype: content_type(ctype), hash: Utils.encode16(hash), signature: Utils.encode64(signature)}
  end

  defp fun(x = %{args: args, ctype: 0, hash: hash, signature: signature}) do
    %{x | args: args, ctype: @craw, hash: Utils.encode16(hash), signature: Utils.encode64(signature)}
  end

  defp fun(x = %{args: args, ctype: 1, hash: hash, signature: signature}) do
    %{
      x
      | args: @json.decode!(args),
        ctype: @cjson,
        hash: Utils.encode16(hash),
        signature: Utils.encode64(signature)
    }
  end

  defp fun(x = %{args: args, ctype: 2, hash: hash, signature: signature}) do
    %{
      x
      | args: CBOR.Decoder.decode(args) |> elem(0),
        ctype: @ccbor,
        hash: Utils.encode16(hash),
        signature: Utils.encode64(signature)
    }
  end

  def content_type(1), do: @cjson
  def content_type(2), do: @ccbor
  def content_type(_), do: @craw

  def craw, do: 0
  def cjson, do: 1
  def ccbor, do: 2
end
