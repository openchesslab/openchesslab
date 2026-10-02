defmodule Analysis.GameSearch.PostgresQuery do
  @moduledoc false

  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordQuery.Postgres, as: GameRecordPostgres
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.Postgres, as: PositionPostgres

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
        )::bigint AS maximum_record_row_id,
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
        last_position_id,
        last_occurrence_id,
        last_record_row_id,
        limit
      )
      when is_integer(maximum_position_id) and maximum_position_id >= 0 and
             is_integer(maximum_occurrence_id) and maximum_occurrence_id >= 0 and
             is_integer(maximum_record_row_id) and maximum_record_row_id >= 0 and
             is_integer(last_position_id) and last_position_id > 0 and
             is_integer(last_occurrence_id) and last_occurrence_id > 0 and
             is_integer(last_record_row_id) and last_record_row_id > 0 and is_integer(limit) and
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

      last_position_parameter =
        maximum_record_parameter + 1

      last_occurrence_parameter =
        last_position_parameter + 1

      last_record_parameter =
        last_occurrence_parameter + 1

      limit_parameter =
        last_record_parameter + 1

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
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint,
          $#{last_record_parameter}::bigint
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
            last_position_id,
            last_occurrence_id,
            last_record_row_id,
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
           PositionPostgres.compile_predicate(
             position_query,
             1
           ),
         {
           :ok,
           record_predicate,
           record_parameters,
           next_parameter
         } <-
           GameRecordPostgres.compile_predicate(
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
end
