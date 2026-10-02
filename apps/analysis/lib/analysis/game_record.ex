defmodule Analysis.GameRecord do
  @moduledoc """
  A concrete played game referencing canonical chess content in PostgreSQL.

  Multiple game records may reference the same canonical game when the
  exact same chess content was played in different contexts.

  Player names, event information, result, source and move-number
  context belong to the game record rather than to canonical game
  identity.
  """

  alias Analysis.GameStart
  alias Analysis.GameStore

  @type id :: binary()
  @type game_id :: GameStore.game_id()

  @type metadata_scalar ::
          binary()
          | boolean()
          | integer()
          | float()
          | nil

  @type metadata_value ::
          metadata_scalar()
          | [metadata_value()]
          | %{optional(binary()) => metadata_value()}

  @type metadata ::
          %{optional(binary()) => metadata_value()}

  @type t :: %__MODULE__{
          id: id(),
          game_id: game_id(),
          start: GameStart.t(),
          metadata: metadata()
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
  def new(id, game_id) do
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
          metadata()
        ) :: t()
  def new(id, game_id, metadata) when is_map(metadata) do
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
          metadata()
        ) :: t()
  def new(id, game_id, %GameStart{} = start, metadata)
      when is_binary(id) and byte_size(id) > 0 and is_integer(game_id) and game_id > 0 and
             is_map(metadata) do
    if valid_metadata?(metadata) do
      %__MODULE__{
        id: id,
        game_id: game_id,
        start: start,
        metadata: metadata
      }
    else
      raise ArgumentError,
            "game record metadata must be a JSON-compatible object with string keys"
    end
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

  @spec metadata(t()) :: metadata()
  def metadata(%__MODULE__{metadata: metadata}) do
    metadata
  end

  @spec valid_metadata?(term()) :: boolean()
  def valid_metadata?(metadata) when is_map(metadata) do
    json_value?(metadata)
  end

  def valid_metadata?(_metadata) do
    false
  end

  defp json_value?(value) when is_map(value) do
    Enum.all?(
      value,
      fn {key, nested_value} ->
        is_binary(key) and
          json_value?(nested_value)
      end
    )
  end

  defp json_value?([]) do
    true
  end

  defp json_value?([head | tail]) do
    json_value?(head) and
      json_value?(tail)
  end

  defp json_value?(value)
       when is_binary(value) or is_boolean(value) or is_nil(value) or is_integer(value) or
              is_float(value) do
    true
  end

  defp json_value?(_value) do
    false
  end
end
