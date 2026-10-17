defmodule Analysis.GameRecordQuery do
  @moduledoc """
  Builds queries over concrete played-game records.

  Record queries describe predicates over durable game-record metadata
  independently of the persistence engine that executes them.
  """

  alias Analysis.GameRecord

  @type t ::
          true
          | false
          | {:metadata_contains, GameRecord.metadata()}
          | {:metadata_value_contains, binary(), binary()}
          | {:metadata_value_between, binary(), binary() | nil, binary() | nil}
          | {:metadata_int_between, binary(), integer() | nil, integer() | nil}
          | {:and, [t()]}
          | {:or, [t()]}

  @spec metadata_contains(GameRecord.metadata()) :: t()
  def metadata_contains(metadata) when is_map(metadata) do
    if GameRecord.valid_metadata?(metadata) do
      {:metadata_contains, metadata}
    else
      raise ArgumentError,
            "game record query metadata must be a JSON-compatible object with string keys"
    end
  end

  @doc """
  Substring match (case-insensitive) on a single metadata value, for the
  search UI's name fields where exact JSONB containment is too strict.
  """
  @spec metadata_value_contains(binary(), binary()) :: t()
  def metadata_value_contains(key, substring) when is_binary(key) and is_binary(substring) do
    {:metadata_value_contains, key, substring}
  end

  @doc """
  Lexicographic range on a single metadata value, for date-shaped strings
  ("2026.09.12" sorts chronologically). Either bound may be nil (open);
  rows without the key never match a bounded range.
  """
  @spec metadata_value_between(binary(), binary() | nil, binary() | nil) :: t()
  def metadata_value_between(key, minimum, maximum)
      when is_binary(key) and (is_binary(minimum) or is_nil(minimum)) and
             (is_binary(maximum) or is_nil(maximum)) do
    {:metadata_value_between, key, minimum, maximum}
  end

  @doc """
  Numeric range on a single metadata value (stored as a string in JSONB).
  Rows whose value is not a plain integer string never match.
  """
  @spec metadata_int_between(binary(), integer() | nil, integer() | nil) :: t()
  def metadata_int_between(key, minimum, maximum)
      when is_binary(key) and (is_integer(minimum) or is_nil(minimum)) and
             (is_integer(maximum) or is_nil(maximum)) do
    {:metadata_int_between, key, minimum, maximum}
  end

  @spec all([t()]) :: t()
  def all(queries) when is_list(queries), do: {:and, queries}

  @spec any([t()]) :: t()
  def any(queries) when is_list(queries), do: {:or, queries}

  @spec match_all() :: t()
  def match_all do
    true
  end

  @spec match_none() :: t()
  def match_none do
    false
  end
end
