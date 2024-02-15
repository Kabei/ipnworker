defmodule PayService do
  require Sqlite

  def get(id) do
    db_ref = :persistent_term.get(:main_conn)

    case Sqlite.fetch("get_paysrv", [id]) do
      nil ->
        nil

      [name, extra] ->
        extras = :erlang.element(1, CBOR.Decoder.decode(extra))
        %{id: id, name: name} |> Map.merge(extras)
    end
  end

  def create(id, name, extra) do
    db_ref = :persistent_term.get(:main_conn)
    Sqlite.step("insert_paysrv", [id, name, extra])
  end

  def update(map, id) do
    db_ref = :persistent_term.get(:main_conn)
    Sqlite.update("pay.serv", map, id: id)
  end

  def remove(id) do
    db_ref = :persistent_term.get(:main_conn)
    Sqlite.step("delete_paysrv", [id])
    Sqlite.step("delete_all_subpay", [id])
  end
end

defmodule SubPay do
  require Sqlite

  def subscribe(id, payer, token, extra) do
    db_ref = :persistent_term.get(:main_conn)
    Sqlite.step("insert_subpay", [id, payer, token, CBOR.encode(extra)])
  end

  def get(id, payer, token) do
    db_ref = :persistent_term.get(:main_conn)

    case Sqlite.fetch("get_subpay", [id, payer, token]) do
      nil -> nil
      extra -> :erlang.element(1, CBOR.Decoder.decode(extra))
    end
  end

  def unsubscribe(id, payer, token) do
    db_ref = :persistent_term.get(:main_conn)
    Sqlite.step("delete_subpay", [id, payer, token])
  end
end
