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

  @spec metadata_contains(GameRecord.metadata()) :: t()
  def metadata_contains(metadata) when is_map(metadata) do
    if GameRecord.valid_metadata?(metadata) do
      {:metadata_contains, metadata}
    else
      raise ArgumentError,
            "game record query metadata must be a JSON-compatible object with string keys"
    end
  end

  @spec match_all() :: t()
  def match_all do
    true
  end

  @spec match_none() :: t()
  def match_none do
    false
  end
end
