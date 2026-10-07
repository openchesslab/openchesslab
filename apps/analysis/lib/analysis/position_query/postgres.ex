defmodule Analysis.PositionQuery.Postgres do
  @moduledoc """
  Translates position-domain predicates to PostgreSQL predicates.

  Generated predicates expect the canonical positions relation to use
  the SQL alias `p`.
  """

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQueryNormalizer
  alias Chess.Position
  alias Chess.PositionCodec

  @spec compile_predicate(
          PositionQuery.t(),
          pos_integer()
        ) ::
          {:ok, String.t(), [term()], pos_integer()}
          | {:error, term()}
  def compile_predicate(query, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    query
    |> PositionQueryNormalizer.normalize()
    |> do_compile_predicate(
      [],
      next_parameter
    )
  end

  defp do_compile_predicate(true, parameters, next_parameter) do
    {
      :ok,
      "TRUE",
      parameters,
      next_parameter
    }
  end

  defp do_compile_predicate(false, parameters, next_parameter) do
    {
      :ok,
      "FALSE",
      parameters,
      next_parameter
    }
  end

  defp do_compile_predicate({:property, :pawn_structure, structure}, parameters, next_parameter) do
    case PositionPawnStructureCodec.encode(structure) do
      {:ok,
       {
         white_pawns,
         black_pawns
       }} ->
        predicate = """
        p.white_pawns = $#{next_parameter}::bigint
        AND p.black_pawns = $#{next_parameter + 1}::bigint
        """

        {
          :ok,
          predicate,
          parameters ++
            [
              white_pawns,
              black_pawns
            ],
          next_parameter + 2
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_compile_predicate({:pawn_structures, structures}, parameters, next_parameter)
       when is_list(structures) do
    queries =
      Enum.map(
        structures,
        fn structure ->
          {
            :property,
            :pawn_structure,
            structure
          }
        end
      )

    do_compile_predicate(
      {
        :or,
        queries
      },
      parameters,
      next_parameter
    )
  end

  defp do_compile_predicate({:property, property, value}, parameters, next_parameter) do
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

  defp do_compile_predicate({:equivalent, %Position{} = position}, parameters, next_parameter) do
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

  defp do_compile_predicate({:equivalent, _position}, _parameters, _next_parameter) do
    {:error, :invalid_equivalent_position}
  end

  defp do_compile_predicate({:not, query}, parameters, next_parameter) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           do_compile_predicate(
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

  defp do_compile_predicate({:and, queries}, parameters, next_parameter) do
    compile_group(
      queries,
      "AND",
      "TRUE",
      parameters,
      next_parameter
    )
  end

  defp do_compile_predicate({:or, queries}, parameters, next_parameter) do
    compile_group(
      queries,
      "OR",
      "FALSE",
      parameters,
      next_parameter
    )
  end

  defp do_compile_predicate(_query, _parameters, _next_parameter) do
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
        case do_compile_predicate(
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
