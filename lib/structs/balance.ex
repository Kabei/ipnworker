defmodule Ippan.Balance do
  @type t :: %__MODULE__{
          id: binary(),
          token: binary(),
          amount: non_neg_integer(),
          locked: non_neg_integer(),
          created_at: integer(),
          updated_at: integer()
        }

  defstruct id: nil,
            token: nil,
            amount: 0,
            locked: 0,
            created_at: nil,
            updated_at: nil

  def to_list(x) do
    [
      x.id,
      x.token,
      x.amount,
      x.locked,
      x.created_at,
      x.updated_at
    ]
  end

  def to_tuple(x) do
    {
      x.id,
      x.token,
      x.amount,
      x.locked,
      x.created_at,
      x.updated_at
    }
  end

  def to_map({id, token, amount, locked, created_at, updated_at}) do
    %{
      id: id,
      token: token,
      amount: amount,
      locked: locked,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def to_map([id, token, amount, locked, created_at, updated_at]) do
    %{
      id: id,
      token: token,
      amount: amount,
      locked: locked,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
