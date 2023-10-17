defmodule Ippan.Domain do
  @behaviour Ippan.Struct
  @type t :: %__MODULE__{
          name: String.t(),
          owner: binary(),
          email: String.t(),
          avatar: String.t(),
          records: non_neg_integer(),
          enabled: boolean(),
          created_at: non_neg_integer(),
          renewed_at: non_neg_integer(),
          updated_at: non_neg_integer()
        }

  @impl true
  def optionals, do: ~w(email avatar)

  @impl true
  def editable, do: ~w(owner email avatar)

  @doc "Return subdomain and domain in a tuple from hostname or list hostname"
  def split(hostname_parts) when is_list(hostname_parts) do
    domain = Enum.take(hostname_parts, -2)
    subdomain = hostname_parts -- domain

    {Enum.join(subdomain, "."), Enum.join(domain, ".")}
  end

  def split(hostname) do
    parts = String.split(hostname, ".")

    domain = Enum.take(parts, -2)
    subdomain = parts -- domain

    {Enum.join(subdomain, "."), Enum.join(domain, ".")}
  end

  def join(subdomain, domain) do
    Enum.join([subdomain, domain], ".")
  end

  def price(name, days) do
    x =
      name
      |> String.split(".")
      |> List.first()
      |> String.length()

    base =
      cond do
        x <= 5 ->
          1000

        x <= 8 ->
          750

        true ->
          500
      end

    base * days
  end

  defstruct name: nil,
            owner: nil,
            email: nil,
            avatar: nil,
            records: 0,
            enabled: true,
            created_at: nil,
            renewed_at: nil,
            updated_at: nil

  @impl true
  def to_tuple(x) do
    {x.name, x}
  end

  @impl true
  def to_list(x) do
    [
      x.name,
      x.owner,
      x.email,
      x.avatar,
      x.records,
      x.enabled,
      x.created_at,
      x.renewed_at,
      x.updated_at
    ]
  end

  @impl true
  def to_map({_name, map}), do: map

  @impl true

  def list_to_map([
        name,
        owner,
        email,
        avatar,
        records,
        enabled,
        created_at,
        renewed_at,
        updated_at
      ]) do
    %{
      name: name,
      owner: owner,
      email: email,
      avatar: avatar,
      records: records,
      enabled: enabled,
      created_at: created_at,
      renewed_at: renewed_at,
      updated_at: updated_at
    }
  end

  @impl true
  def list_to_tuple([name | _] = x) do
    {name, list_to_map(x)}
  end

  defmacro insert(args) do
    quote location: :keep do
      SqliteStore.step("insert_domain", unquote(args))
    end
  end

  defmacro get(id) do
    quote location: :keep do
      SqliteStore.get(:token, "get_domain", unquote(id), Ippan.Token)
    end
  end

  defmacro exists?(name) do
    quote bind_quoted: [name: name], location: :keep do
      SqliteStore.exists?("exists_domain", [name])
    end
  end

  defmacro owner?(name, owner) do
    quote bind_quoted: [name: name, owner: owner], location: :keep do
      SqliteStore.exists?("owner_domain", [name, owner])
    end
  end

  defmacro renew(name, owner, renewed_at, updated_at) do
    quote bind_quoted: [name: name, owner: owner, renewed_at: renewed_at, updated_at: updated_at],
          location: :keep do
      SqliteStore.step("renew_domain", [name, owner, renewed_at, updated_at])
    end
  end

  defmacro delete(name, owner) do
    quote bind_quoted: [name: name, owner: owner], location: :keep do
      SqliteStore.step("delete_domain", [name, owner])
    end
  end

  defmacro update(map, name) do
    quote location: :keep do
      SqliteStore.update("assets.domain", unquote(map), name: unquote(name))
    end
  end
end
