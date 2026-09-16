defmodule PositionDB.EquivalenceContext do
  alias PositionDB.EquivalenceIndex

  @type t :: %__MODULE__{
          index: EquivalenceIndex.t(),
          key_function: (term() -> term()),
          matcher: (term(), term() -> boolean())
        }

  defstruct [
    :index,
    :key_function,
    :matcher
  ]

  @spec new(
          (term() -> term()),
          (term(), term() -> boolean())
        ) :: t()
  def new(key_function, matcher) do
    %__MODULE__{
      index: EquivalenceIndex.new(),
      key_function: key_function,
      matcher: matcher
    }
  end

  @spec add(t(), term(), non_neg_integer()) :: t()
  def add(context, position, position_id) do
    key = context.key_function.(position)

    %{
      context
      | index:
          EquivalenceIndex.add(
            context.index,
            key,
            position_id
          )
    }
  end

  @spec delete(t(), term(), non_neg_integer()) :: t()
  def delete(context, position, position_id) do
    key = context.key_function.(position)

    %{
      context
      | index:
          EquivalenceIndex.delete(
            context.index,
            key,
            position_id
          )
    }
  end
end
