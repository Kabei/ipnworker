defmodule Ippan.Ecto.Filters do
  import Ecto.Query, only: [limit: 2, offset: 2]

  @default_limit 50
  @max_limit 200

  def filter_limit(query, %{"lmt" => "unlimited"}), do: query

  def filter_limit(query, %{"lmt" => num_limit}) do
    num = :erlang.binary_to_integer(num_limit)

    if num > @max_limit do
      limit(query, ^@max_limit)
    else
      limit(query, ^num)
    end
  end

  def filter_limit(query, _), do: limit(query, ^@default_limit)

  def filter_offset(query, %{"starts" => num_offset}) do
    offset(query, ^num_offset)
  end

  def filter_offset(query, _params), do: query
end
