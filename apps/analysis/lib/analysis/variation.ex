defmodule Analysis.Variation do
  @moduledoc """
  An ordered sequence of chess transitions.
  """

  alias Analysis.Transition

  @type t :: %__MODULE__{
          transitions: [Transition.t()]
        }

  defstruct transitions: []

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec new([Transition.t()]) :: t()
  def new(transitions) when is_list(transitions) do
    %__MODULE__{
      transitions: transitions
    }
  end
end
