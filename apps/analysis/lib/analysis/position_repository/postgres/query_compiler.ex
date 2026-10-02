defmodule Analysis.PositionRepository.Postgres.QueryCompiler do
  @moduledoc false

  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.Postgres, as: PostgresQuery

  @spec compile(
          PositionQuery.t(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer()
        ) ::
          {:ok, String.t(), [term()]}
          | {:error, term()}
  def compile(query, after_position_id, maximum_position_id, limit)
      when is_integer(after_position_id) and after_position_id >= 0 and
             is_integer(maximum_position_id) and maximum_position_id >= 0 and is_integer(limit) and
             limit > 0 do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           PostgresQuery.compile_predicate(
             query,
             1
           ) do
      after_parameter =
        next_parameter

      maximum_parameter =
        after_parameter + 1

      limit_parameter =
        maximum_parameter + 1

      sql = """
      SELECT p.id
      FROM positions AS p
      WHERE
        p.id > $#{after_parameter}::bigint
        AND p.id <= $#{maximum_parameter}::bigint
        AND (#{predicate})
      ORDER BY p.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            after_position_id,
            maximum_position_id,
            limit
          ]
      }
    end
  end
end
