defmodule Analysis.Game do
  @moduledoc """
  A canonical played chess game.

  A game contains the factual played move sequence from its initial
  position. Variations, comments and hypothetical edits belong to an
  Analysis rather than to the canonical game.
  """

  alias Analysis.GameStart
  alias Chess.Move

  @type id :: term()
  @type position_id :: term()

  @type t :: %__MODULE__{
          id: id(),
          initial_position_id: position_id(),
          start: GameStart.t(),
          moves: [Move.t()],
          metadata: map()
        }

  @enforce_keys [
    :id,
    :initial_position_id,
    :start,
    :moves
  ]

  defstruct id: nil,
            initial_position_id: nil,
            start: nil,
            moves: [],
            metadata: %{}

  @spec new(id(), position_id()) :: t()
  def new(id, initial_position_id) do
    new(
      id,
      initial_position_id,
      GameStart.standard(),
      [],
      %{}
    )
  end

  @spec new(id(), position_id(), [Move.t()]) :: t()
  def new(id, initial_position_id, moves)
      when is_list(moves) do
    new(
      id,
      initial_position_id,
      GameStart.standard(),
      moves,
      %{}
    )
  end

  @spec new(id(), position_id(), [Move.t()], map()) :: t()
  def new(id, initial_position_id, moves, metadata)
      when is_list(moves) and is_map(metadata) do
    new(
      id,
      initial_position_id,
      GameStart.standard(),
      moves,
      metadata
    )
  end

  @spec new(
          id(),
          position_id(),
          GameStart.t(),
          [Move.t()],
          map()
        ) :: t()
  def new(
        id,
        initial_position_id,
        %GameStart{} = start,
        moves,
        metadata
      )
      when is_list(moves) and is_map(metadata) do
    %__MODULE__{
      id: id,
      initial_position_id: initial_position_id,
      start: start,
      moves: moves,
      metadata: metadata
    }
  end

  @spec id(t()) :: id()
  def id(%__MODULE__{id: id}), do: id

  @spec initial_position_id(t()) :: position_id()
  def initial_position_id(%__MODULE__{
        initial_position_id: initial_position_id
      }) do
    initial_position_id
  end

  @spec start(t()) :: GameStart.t()
  def start(%__MODULE__{start: start}), do: start

  @spec moves(t()) :: [Move.t()]
  def moves(%__MODULE__{moves: moves}), do: moves

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata
end
