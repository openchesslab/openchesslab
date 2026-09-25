defmodule Analysis.Room do
  @moduledoc false

  @type id :: term()
  @type analysis_id :: Analysis.Analysis.id()

  @type t :: %__MODULE__{
          id: id(),
          analysis_ids: [analysis_id()]
        }

  @enforce_keys [:id]
  defstruct id: nil, analysis_ids: []

  @spec new(id()) :: t()
  def new(id) do
    %__MODULE__{id: id}
  end

  @spec id(t()) :: id()
  def id(%__MODULE__{id: id}) do
    id
  end

  @spec analysis_ids(t()) :: [analysis_id()]
  def analysis_ids(%__MODULE__{analysis_ids: analysis_ids}) do
    analysis_ids
  end

  @spec has_analysis?(t(), analysis_id()) :: boolean()
  def has_analysis?(%__MODULE__{analysis_ids: analysis_ids}, analysis_id) do
    analysis_id in analysis_ids
  end

  @spec add_analysis(t(), analysis_id()) :: t()
  def add_analysis(%__MODULE__{} = room, analysis_id) do
    if has_analysis?(room, analysis_id) do
      room
    else
      %{room | analysis_ids: room.analysis_ids ++ [analysis_id]}
    end
  end

  @spec remove_analysis(t(), analysis_id()) :: t()
  def remove_analysis(%__MODULE__{} = room, analysis_id) do
    %{
      room
      | analysis_ids:
          Enum.reject(
            room.analysis_ids,
            &(&1 == analysis_id)
          )
    }
  end
end
