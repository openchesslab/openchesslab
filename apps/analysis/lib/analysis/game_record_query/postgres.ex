defmodule Analysis.GameRecordQuery.Postgres do
  @moduledoc """
  Translates game-record domain predicates to PostgreSQL predicates.

  Generated predicates expect the game-record relation to use
  the SQL alias `gr`.
  """

  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery

  @spec compile_predicate(
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          {:ok, String.t(), [term()], pos_integer()}
          | {:error, term()}
  def compile_predicate(true, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {
      :ok,
      "TRUE",
      [],
      next_parameter
    }
  end

  def compile_predicate(false, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {
      :ok,
      "FALSE",
      [],
      next_parameter
    }
  end

  def compile_predicate({:metadata_contains, metadata}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    if GameRecord.valid_metadata?(metadata) do
      {
        :ok,
        "gr.metadata @> $#{next_parameter}::jsonb",
        [
          metadata
        ],
        next_parameter + 1
      }
    else
      {:error, :invalid_game_record_query}
    end
  end

  def compile_predicate(_query, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {:error, :unsupported_game_record_query}
  end
end
