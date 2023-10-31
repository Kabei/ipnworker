defmodule Ippan.Node do
  @behaviour Ippan.Struct

  @type t :: %__MODULE__{
          id: binary,
          hostname: charlist(),
          port: non_neg_integer(),
          role: [binary] | nil,
          pubkey: binary,
          net_pubkey: binary,
          avatar: binary | nil,
          created_at: integer(),
          updated_at: integer()
        }

  defstruct [
    :id,
    :hostname,
    :port,
    :role,
    :pubkey,
    :net_pubkey,
    :avatar,
    :created_at,
    :updated_at
  ]

  # @fields __MODULE__.__struct__() |> Map.keys() |> Enum.map(&to_string(&1)) |> IO.inspect()
  # @spec fields :: [binary()]
  # def fields, do: @fields

  @impl true
  def editable, do: ~w(hostname port role avatar)

  @impl true
  def optionals, do: ~w(avatar)

  @impl true
  def to_list(x) do
    [
      x.id,
      x.hostname,
      x.port,
      CBOR.encode(x.role),
      x.pubkey,
      x.net_pubkey,
      x.avatar,
      x.created_at,
      x.updated_at
    ]
  end

  @impl true
  def list_to_tuple([id | _] = x) do
    {id, list_to_map(x)}
  end

  @impl true
  def to_tuple(x) do
    {x.id, x}
  end

  @impl true
  def list_to_map([
        id,
        hostname,
        port,
        role,
        pubkey,
        net_pubkey,
        avatar,
        created_at,
        updated_at
      ]) do
    %{
      id: id,
      hostname: hostname,
      port: port,
      role: :erlang.element(1, CBOR.Decoder.decode(role)),
      pubkey: pubkey,
      net_pubkey: net_pubkey,
      avatar: avatar,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  @impl true
  def to_map({_id, x}), do: x

  defmacro insert(node) do
    quote do
      Sqlite.step("insert_node", unquote(node))
    end
  end

  defmacro get(id) do
    quote location: :keep do
      Sqlite.fetch("get_node", [unquote(id)])
      |> case do
        nil -> nil
        x -> Ippan.Node.list_to_map(x)
      end
    end
  end

  defmacro fetch(id) do
    quote location: :keep do
      Sqlite.fetch("get_node", [unquote(id)])
    end
  end

  defmacro total do
    quote location: :keep do
      Sqlite.one("total_nodes", [])
    end
  end

  defmacro delete(id) do
    quote location: :keep do
      Sqlite.step("delete_node", [unquote(id)])
    end
  end

  defmacro delete_all do
    quote location: :keep do
      Sqlite.step("delete_nodes", [])
    end
  end
end
