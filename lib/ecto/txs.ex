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
    field(:ix, :integer)
    field(:block, :integer)
    field(:hash, :binary)
    field(:type, :integer)
    field(:from, :binary)
    field(:status, :integer)
    field(:nonce, :integer)
    field(:size, :integer)
    field(:ctype, :integer)
    field(:args, :binary)
  end

  @select ~w(ix block hash type from status nonce size ctype args)a

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

  def one(vid, height, hash16) do
    hash = Base.decode16!(hash16, case: :mixed)

    from(b in Block,
      join: tx in Tx,
      on: tx.block == b.id,
      where:
        b.creator == ^vid and b.height == ^height and
          tx.hash == ^hash,
      select: map(tx, @select),
      limit: 1
    )
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
    |> filter_below(params)
    |> filter_select()
    |> sort(params)
    |> Repo.all()
    |> Enum.map(&fun(&1))
  end

  defp filter_select(query) do
    select(query, [tx], map(tx, @select))
  end

  defp filter_below(query, %{"below" => id}) do
    where(query, [tx], tx.block < ^id)
  end

  defp filter_below(query, _), do: query

  defp sort(query, %{"sort" => "oldest"}), do: order_by(query, [tx], asc: tx.block)
  defp sort(query, _), do: order_by(query, [tx], desc: tx.block)

  defp fun(x = %{args: nil, hash: hash, ctype: ctype}) do
    %{x | hash: Utils.encode16(hash), ctype: ctype(ctype)}
  end

  defp fun(x = %{args: args, ctype: 0, hash: hash}) do
    %{x | hash: Utils.encode16(hash), ctype: @craw, args: args}
  end

  defp fun(x = %{args: args, ctype: 1, hash: hash}) do
    %{
      x
      | hash: Utils.encode16(hash),
        ctype: @cjson,
        args: @json.decode!(args)
    }
  end

  defp fun(x = %{args: args, ctype: 2, hash: hash}) do
    %{
      x
      | hash: Utils.encode16(hash),
        ctype: @ccbor,
        args: CBOR.Decoder.decode(args) |> elem(0)
    }
  end

  defp ctype(0), do: @craw
  defp ctype(1), do: @cjson
  defp ctype(2), do: @ccbor

  defmacro binary_type do
    quote do
      0
    end
  end

  defmacro json_type do
    quote do
      1
    end
  end

  defmacro cbor_type do
    quote do
      2
    end
  end
end
