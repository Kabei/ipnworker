defmodule Ippan.Ecto.Filters do
  # import Ecto.Query, only: [limit: 2, offset: 2]
  import Ecto.Query, only: [offset: 2]

  # @compile :inline_list_funcs
  # @compile {:inline, [filter_limit: 2, filter_limit: 4, filter_offset: 2]}

  # @default_limit 50
  # @max_limit 200

  def filter_limit(query, _), do: query

  # def filter_limit(query, params) do
  #   filter_limit(query, params, @default_limit, @max_limit)
  # end

  # def filter_limit(query, %{"lmt" => num_limit}, default, max)
  #     when is_integer(num_limit) do
  #   case num_limit do
  #     x when x in 1..max ->
  #       limit(query, ^x)

  #     _ ->
  #       limit(query, ^default)
  #   end
  # end

  # def filter_limit(query, %{"lmt" => num_limit}, default, max) do
  #   filter_limit(query, %{"lmt" => String.to_integer(num_limit)}, default, max)
  # end

  # def filter_limit(query, _params, default, _max) do
  #   limit(query, ^default)
  # end

  def filter_offset(query, %{"starts" => num_offset}) when is_integer(num_offset) do
    offset(query, ^num_offset)
  end

  def filter_offset(query, %{"starts" => num_offset}) do
    try do
      x = String.to_integer(num_offset)
      filter_offset(query, %{"starts" => x})
    catch
      _error ->
        offset(query, 0)
    end
  end

  def filter_offset(query, _params), do: query
end
