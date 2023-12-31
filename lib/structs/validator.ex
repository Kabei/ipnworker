defmodule Ippan.Validator do
  alias Ippan.Utils
  @behaviour Ippan.Struct
  @type t :: %__MODULE__{
          id: non_neg_integer(),
          hostname: String.t(),
          port: integer(),
          name: String.t(),
          owner: binary(),
          class: String.t(),
          pubkey: binary(),
          net_pubkey: binary(),
          avatar: String.t() | nil,
          fa: integer(),
          fb: integer(),
          active: boolean(),
          failures: integer(),
          env: map(),
          created_at: non_neg_integer(),
          updated_at: non_neg_integer()
        }

  defstruct [
    :id,
    :hostname,
    :port,
    :name,
    :owner,
    :pubkey,
    :net_pubkey,
    :avatar,
    :fa,
    :fb,
    :created_at,
    :updated_at,
    active: false,
    failures: 0,
    env: %{},
    class: ""
  ]

  @impl true
  def editable, do: ~w(hostname port name avatar fa fb owner pubkey net_pubkey class)
  @impl true
  def optionals, do: ~w(avatar env)

  @impl true
  def to_list(x) do
    [
      x.id,
      x.hostname,
      x.port,
      x.name,
      x.owner,
      x.class,
      x.pubkey,
      x.net_pubkey,
      x.avatar,
      x.fa,
      x.fb,
      if(x.active == true, do: 1, else: 0),
      x.failures,
      CBOR.encode(x.env),
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
        name,
        owner,
        class,
        pubkey,
        net_pubkey,
        avatar,
        fa,
        fb,
        active,
        failures,
        env,
        created_at,
        updated_at
      ]) do
    %{
      id: id,
      hostname: hostname,
      port: port,
      name: name,
      owner: owner,
      class: class,
      avatar: avatar,
      pubkey: pubkey,
      net_pubkey: net_pubkey,
      fb: fb,
      fa: fa,
      active: if(active == 1, do: true, else: false),
      failures: failures,
      env: :erlang.element(1, CBOR.Decoder.decode(env)),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  @impl true
  def to_map({_id, x}) do
    x
  end

  def to_text(x = %{pubkey: pk, net_pubkey: npk}) do
    %{x | pubkey: Utils.encode64(pk), net_pubkey: Utils.encode64(npk)}
  end

  def calc_price(total), do: (total + 1) * EnvStore.validator_price()

  require Sqlite

  defmacro insert(args) do
    quote location: :keep do
      Sqlite.step("insert_validator", unquote(args))
    end
  end

  defmacro get(id) do
    quote location: :keep do
      Sqlite.get(:validator, "get_validator", unquote(id), Ippan.Validator)
    end
  end

  defmacro next_id do
    quote location: :keep do
      Sqlite.one("next_id_validator")
    end
  end

  defmacro exists?(id) do
    quote location: :keep do
      Sqlite.exists?("exists_validator", [unquote(id)])
    end
  end

  defmacro exists_host?(hostname) do
    quote location: :keep do
      Sqlite.exists?("exists_host_validator", [unquote(hostname)])
    end
  end

  defmacro owner?(id, owner) do
    quote bind_quoted: [id: id, owner: owner], location: :keep do
      Sqlite.exists?("owner_validator", [id, owner])
    end
  end

  defmacro total do
    quote location: :keep do
      Sqlite.one("total_validators", [], 0)
    end
  end

  defmacro update(map, id) do
    quote bind_quoted: [map: map, id: id], location: :keep do
      :ets.delete(:validator, id)
      Sqlite.update("blockchain.validator", map, id: id)
    end
  end

  defmacro put_active(id, active, round_id) do
    quote bind_quoted: [id: id, active: active, round: round_id], location: :keep do
      :ets.delete(:validator, id)
      active = if active == true, do: 1, else: 0
      Sqlite.update("blockchain.validator", %{"active" => active, "updated_at" => round}, id: id)
    end
  end

  defmacro delete(id) do
    quote bind_quoted: [id: id], location: :keep do
      if id == :persistent_term.get(:vid) do
        Logger.warning("Delete validator #{id}")
        # System.halt()
      end

      :ets.delete(:validator, id)
      Sqlite.step("delete_validator", [id])
    end
  end
end
