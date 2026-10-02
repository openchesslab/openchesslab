defmodule Analysis.GameSearchRepository.Postgres.QueryCompiler do
  @moduledoc false

  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.PositionQuery
  alias Analysis.PositionRepository.Postgres.QueryCompiler, as: PositionQueryCompiler

  @spec compile_first(
          PositionQuery.t(),
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          {:ok, String.t(), [term()]}
          | {:error, term()}
  def compile_first(position_query, record_query, limit) when is_integer(limit) and limit > 0 do
    with {
           :ok,
           position_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_predicates(
             position_query,
             record_query
           ) do
      limit_parameter =
        next_parameter

      sql = """
      WITH bounds AS (
        SELECT
          COALESCE(
            (
              SELECT max(id)
              FROM positions
            ),
            0
          )::bigint AS maximum_position_id,
          COALESCE(
            (
              SELECT max(id)
              FROM game_occurrences
            ),
            0
          )::bigint AS maximum_occurrence_id,
          COALESCE(
            (
              SELECT max(id)
              FROM game_records
            ),
            0
          )::bigint AS maximum_record_row_id
      )
      SELECT
        bounds.maximum_position_id,
        bounds.maximum_occurrence_id,
        bounds.maximum_record_row_id,
        p.id,
        go.id,
        go.game_id,
        go.ply,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata
      FROM bounds
      JOIN positions AS p
        ON p.id <= bounds.maximum_position_id
      JOIN game_occurrences AS go
        ON go.position_id = p.id
        AND go.id <= bounds.maximum_occurrence_id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
        AND gr.id <= bounds.maximum_record_row_id
      WHERE
        (#{position_predicate})
        AND (#{record_predicate})
      ORDER BY
        p.id,
        go.id,
        gr.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            limit
          ]
      }
    end
  end

  @spec compile_next(
          PositionQuery.t(),
          GameRecordQuery.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, String.t(), [term()]}
          | {:error, term()}
  def compile_next(
        position_query,
        record_query,
        maximum_position_id,
        maximum_occurrence_id,
        maximum_record_row_id,
        after_position_id,
        after_occurrence_id,
        after_record_row_id,
        limit
      )
      when is_integer(maximum_position_id) and maximum_position_id >= 0 and
             is_integer(maximum_occurrence_id) and maximum_occurrence_id >= 0 and
             is_integer(maximum_record_row_id) and maximum_record_row_id >= 0 and
             is_integer(after_position_id) and after_position_id > 0 and
             is_integer(after_occurrence_id) and after_occurrence_id > 0 and
             is_integer(after_record_row_id) and after_record_row_id > 0 and is_integer(limit) and
             limit > 0 do
    with {
           :ok,
           position_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_predicates(
             position_query,
             record_query
           ) do
      maximum_position_parameter =
        next_parameter

      maximum_occurrence_parameter =
        maximum_position_parameter + 1

      maximum_record_parameter =
        maximum_occurrence_parameter + 1

      after_position_parameter =
        maximum_record_parameter + 1

      after_occurrence_parameter =
        after_position_parameter + 1

      after_record_parameter =
        after_occurrence_parameter + 1

      limit_parameter =
        after_record_parameter + 1

      sql = """
      SELECT
        $#{maximum_position_parameter}::bigint,
        $#{maximum_occurrence_parameter}::bigint,
        $#{maximum_record_parameter}::bigint,
        p.id,
        go.id,
        go.game_id,
        go.ply,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata
      FROM positions AS p
      JOIN game_occurrences AS go
        ON go.position_id = p.id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
      WHERE
        p.id <= $#{maximum_position_parameter}::bigint
        AND go.id <= $#{maximum_occurrence_parameter}::bigint
        AND gr.id <= $#{maximum_record_parameter}::bigint
        AND (
          p.id,
          go.id,
          gr.id
        ) > (
          $#{after_position_parameter}::bigint,
          $#{after_occurrence_parameter}::bigint,
          $#{after_record_parameter}::bigint
        )
        AND (#{position_predicate})
        AND (#{record_predicate})
      ORDER BY
        p.id,
        go.id,
        gr.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_position_id,
            maximum_occurrence_id,
            maximum_record_row_id,
            after_position_id,
            after_occurrence_id,
            after_record_row_id,
            limit
          ]
      }
    end
  end

  defp compile_predicates(position_query, record_query) do
    with {
           :ok,
           position_predicate,
           position_parameters,
           next_parameter
         } <-
           PositionQueryCompiler.compile_predicate(
             position_query,
             1
           ),
         {
           :ok,
           record_predicate,
           record_parameters,
           next_parameter
         } <-
           compile_record_predicate(
             record_query,
             next_parameter
           ) do
      {
        :ok,
        position_predicate,
        record_predicate,
        position_parameters ++
          record_parameters,
        next_parameter
      }
    end
  end

  defp compile_record_predicate(true, next_parameter) do
    {
      :ok,
      "TRUE",
      [],
      next_parameter
    }
  end

  defp compile_record_predicate(false, next_parameter) do
    {
      :ok,
      "FALSE",
      [],
      next_parameter
    }
  end

  defp compile_record_predicate({:metadata_contains, metadata}, next_parameter) do
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
      {:error, :invalid_record_query}
    end
  end

  defp compile_record_predicate(_query, _next_parameter) do
    {:error, :invalid_record_query}
  end
end
