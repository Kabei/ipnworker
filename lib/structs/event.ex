defmodule Ippan.Event do
  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          base: atom(),
          mod: module(),
          fun: atom() | function() | nil,
          deferred: boolean(),
          auth: boolean(),
          validator: integer(),
          before: atom() | function() | nil
        }

  @enforce_keys [:id, :name, :base, :mod, :fun]
  defstruct [
    :id,
    :name,
    :base,
    :mod,
    :fun,
    :before,
    deferred: false,
    validator: 1,
    auth: true
  ]
end
