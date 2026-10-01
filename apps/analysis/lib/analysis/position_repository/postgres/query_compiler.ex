defmodule Analysis.PositionRepository.Postgres.QueryCompiler do
  @moduledoc false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQueryNormalizer
  alias Chess.Position
  alias Chess.PositionCodec

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
    normalized =
      PositionQueryNormalizer.normalize(query)

    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           compile_predicate(
             normalized,
             [],
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

  defp compile_predicate(true, parameters, next_parameter) do
    {
      :ok,
      "TRUE",
      parameters,
      next_parameter
    }
  end

  defp compile_predicate(false, parameters, next_parameter) do
    {
      :ok,
      "FALSE",
      parameters,
      next_parameter
    }
  end

  defp compile_predicate({:property, property, value}, parameters, next_parameter) do
    case PositionPropertyKeyCodec.encode(
           property,
           value
         ) do
      {:ok, encoded_property} ->
        predicate = """
        EXISTS (
          SELECT 1
          FROM position_features AS f
          WHERE
            f.position_id = p.id
            AND f.properties @> ARRAY[$#{next_parameter}::bytea]::bytea[]
        )
        """

        {
          :ok,
          predicate,
          parameters ++
            [
              encoded_property
            ],
          next_parameter + 1
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compile_predicate({:equivalent, %Position{} = position}, parameters, next_parameter) do
    record =
      PositionCodec.encode(position)

    {
      :ok,
      "p.record = $#{next_parameter}::bytea",
      parameters ++
        [
          record
        ],
      next_parameter + 1
    }
  end

  defp compile_predicate({:equivalent, _position}, _parameters, _next_parameter) do
    {:error, :invalid_equivalent_position}
  end

  defp compile_predicate({:not, query}, parameters, next_parameter) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           compile_predicate(
             query,
             parameters,
             next_parameter
           ) do
      {
        :ok,
        "NOT (#{predicate})",
        parameters,
        next_parameter
      }
    end
  end

  defp compile_predicate({:and, queries}, parameters, next_parameter) do
    compile_group(
      queries,
      "AND",
      "TRUE",
      parameters,
      next_parameter
    )
  end

  defp compile_predicate({:or, queries}, parameters, next_parameter) do
    compile_group(
      queries,
      "OR",
      "FALSE",
      parameters,
      next_parameter
    )
  end

  defp compile_predicate(_query, _parameters, _next_parameter) do
    {:error, :unsupported_position_query}
  end

  defp compile_group([], _operator, identity, parameters, next_parameter) do
    {
      :ok,
      identity,
      parameters,
      next_parameter
    }
  end

  defp compile_group(queries, operator, _identity, parameters, next_parameter) do
    queries
    |> Enum.reduce_while(
      {
        :ok,
        [],
        parameters,
        next_parameter
      },
      fn query,
         {
           :ok,
           predicates,
           parameters,
           next_parameter
         } ->
        case compile_predicate(
               query,
               parameters,
               next_parameter
             ) do
          {
            :ok,
            predicate,
            parameters,
            next_parameter
          } ->
            {:cont,
             {
               :ok,
               [
                 predicate
                 | predicates
               ],
               parameters,
               next_parameter
             }}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {
        :ok,
        predicates,
        parameters,
        next_parameter
      } ->
        predicate =
          predicates
          |> Enum.reverse()
          |> Enum.map_join(
            " #{operator} ",
            &"(#{&1})"
          )

        {
          :ok,
          predicate,
          parameters,
          next_parameter
        }

      {:error, reason} ->
        {:error, reason}
    end
  end
end
