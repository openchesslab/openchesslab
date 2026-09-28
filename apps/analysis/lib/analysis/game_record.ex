defmodule Analysis.GameRecord do
  @moduledoc """
  A concrete played game referencing canonical chess content in GameDB.

  Multiple game records may reference the same canonical game when the
  exact same chess content was played in different contexts.

  Player names, event information, result, source and move-number
  context belong to the game record rather than to canonical game
  identity.
  """

  alias Analysis.GameStart

  @type id :: term()
  @type game_id :: GameDB.game_id()

  @type t :: %__MODULE__{
          id: id(),
          game_id: game_id(),
          start: GameStart.t(),
          metadata: map()
        }

  @enforce_keys [
    :id,
    :game_id,
    :start
  ]

  defstruct id: nil,
            game_id: nil,
            start: nil,
            metadata: %{}

  @spec new(
          id(),
          game_id()
        ) :: t()
  def new(
        id,
        game_id
      ) do
    new(
      id,
      game_id,
      GameStart.standard(),
      %{}
    )
  end

  @spec new(
          id(),
          game_id(),
          map()
        ) :: t()
  def new(
        id,
        game_id,
        metadata
      )
      when is_map(metadata) do
    new(
      id,
      game_id,
      GameStart.standard(),
      metadata
    )
  end

  @spec new(
          id(),
          game_id(),
          GameStart.t(),
          map()
        ) :: t()
  def new(
        id,
        game_id,
        %GameStart{} = start,
        metadata
      )
      when is_integer(game_id) and
             game_id > 0 and
             is_map(metadata) do
    %__MODULE__{
      id: id,
      game_id: game_id,
      start: start,
      metadata: metadata
    }
  end

  @spec id(t()) :: id()
  def id(%__MODULE__{id: id}) do
    id
  end

  @spec game_id(t()) :: game_id()
  def game_id(%__MODULE__{game_id: game_id}) do
    game_id
  end

  @spec start(t()) :: GameStart.t()
  def start(%__MODULE__{start: start}) do
    start
  end

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}) do
    metadata
  end
end
