defmodule Ippan.Utils do
    def empty?(nil), do: true
    def empty?(<<>>), do: true
    def empty?([]), do: true
    def empty?(x) when x == %{}, do: true
    def empty?(_), do: false

    def to_atom(nil), do: nil
    def to_atom(text), do: String.to_atom(text)

    @spec rows_to_columns(map() | Keyword.t()) :: {list(), list()}
    def rows_to_columns(map_or_kw) do
      result =
        cond do
          is_map(map_or_kw) ->
            Map.to_list(map_or_kw)

          is_list(map_or_kw) ->
            Keyword.to_list(map_or_kw)
        end
        |> Enum.reduce(%{keys: [], values: []}, fn {key, value}, acc ->
          %{keys: [key | acc.keys], values: [value | acc.values]}
        end)

      keys = Enum.reverse(result.keys)
      values = Enum.reverse(result.values)

      {keys, values}
    end

    #  Fee types:
    #  0 -> by size
    #  1 -> by percent
    #  2 -> fixed price
    # by size
    def calc_fees!(0, fee_amount, _tx_amount, size),
      do: trunc(fee_amount) * size

    # by percent
    def calc_fees!(1, fee_amount, tx_amount, _size),
      do: :math.ceil(tx_amount * fee_amount) |> trunc()

    # fixed price
    def calc_fees!(2, fee_amount, _tx_amount, _size), do: trunc(fee_amount)

    def calc_fees!(_, _, _, _), do: raise(IppanError, "Fee calculation error")

    def get_name_from_node(node_name) do
      node_name |> to_string() |> String.split("@") |> hd
    end

    def my_ip do
      node() |> to_string() |> String.split("@") |> List.last()
    end

    def get_random_node_verifier do
      Node.list() |> Enum.random() |> to_string() |> String.split("@") |> hd
    end

    def delete_oldest_file(dir) do
      dir
      |> Path.expand()
      |> File.ls!()
      |> Enum.sort_by(&File.stat!(&1).mtime)
      |> List.first()
      |> File.rm!()
    end

    def delete_files(dir, timestamp) do
      dir
      |> Path.expand()
      |> File.ls!()
      |> Enum.filter(&(File.stat!(&1).mtime < timestamp))
      |> Enum.each(fn path ->
        File.rm(path)
      end)
    end
  end
