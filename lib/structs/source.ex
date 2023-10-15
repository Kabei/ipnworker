# defmodule Source do
#   alias Ippan.Func.Validator
#   alias Ippan.Event

# @type t :: %__MODULE__{
#         conn: {reference(), map()},
#         hash: binary(),
#         balance: {pid(), :ets.tid()},
#         wallet: {pid(), :ets.tid()},
#         type: non_neg_integer() | Event.t(),
#         id: binary() | nil,
#         validator: Validator.t(),
#         size: non_neg_integer()
#       }
# defstruct [:hash, :conn, :balance, :event, :id, :validator, :node, :timestamp, :size]

# def new(hash, from, validator, size) do
#   conn = :persistent_term.get(:asset_conn)
#   stmts = :persistent_term.get(:asset_stmts)
#   wallet = {DetsPlux.get(:wallet), DetsPlux.get(:tx)}

#     %{
#       conn: {conn, stmts},
#       hash: hash,
#       validator: validator,
#       id: from,
#       stats: stats_db,
#       supply: supply_tx,
#       wallet: {wallet_db, wallet_tx},
#       balance: {balance_db, balance_tx}
#     }
# end
# end

defmodule TxSource do
  defstruct [:hash, :type, :id, :validator, :nonce, :size]
end
