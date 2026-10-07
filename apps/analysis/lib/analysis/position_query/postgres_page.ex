defmodule Analysis.PositionQuery.PostgresPage do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.Postgres, as: PredicateCompiler
  alias Analysis.PositionQueryNormalizer

  @type compile_result ::
          {:ok, String.t(), [term()]}
          | {:error, term()}

  @spec compile_first(
          PositionQuery.t(),
          pos_integer()
        ) ::
          compile_result()
  def compile_first(query, limit) when is_integer(limit) and limit > 0 do
    normalized_query =
      PositionQueryNormalizer.normalize(query)

    case edit_neighborhood_scan(normalized_query) do
      {
        :ok,
        structures,
        residual_query
      } ->
        compile_edit_neighborhood_first(
          structures,
          residual_query,
          limit
        )

      :none ->
        case symmetry_scan(normalized_query) do
          {
            :ok,
            structures,
            residual_query
          } ->
            compile_symmetry_first(
              structures,
              residual_query,
              limit
            )

          :none ->
            compile_generic_first(
              normalized_query,
              limit
            )
        end
    end
  end

  @spec compile_next(
          PositionQuery.t(),
          non_neg_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          compile_result()
  def compile_next(query, maximum_position_id, last_position_id, limit)
      when is_integer(limit) and limit > 0 do
    normalized_query =
      PositionQueryNormalizer.normalize(query)

    case edit_neighborhood_scan(normalized_query) do
      {
        :ok,
        structures,
        residual_query
      } ->
        compile_edit_neighborhood_next(
          structures,
          residual_query,
          maximum_position_id,
          last_position_id,
          limit
        )

      :none ->
        case symmetry_scan(normalized_query) do
          {
            :ok,
            structures,
            residual_query
          } ->
            compile_symmetry_next(
              structures,
              residual_query,
              maximum_position_id,
              last_position_id,
              limit
            )

          :none ->
            compile_generic_next(
              normalized_query,
              maximum_position_id,
              last_position_id,
              limit
            )
        end
    end
  end

  defp edit_neighborhood_scan(
         {:pawn_structure_edit_neighborhood, [_structure | _remaining] = structures}
       ) do
    {
      :ok,
      structures,
      true
    }
  end

  defp edit_neighborhood_scan({:and, queries}) do
    case Enum.find_index(
           queries,
           &edit_neighborhood_node?/1
         ) do
      nil ->
        :none

      index ->
        {
          :pawn_structure_edit_neighborhood,
          structures
        } =
          Enum.at(
            queries,
            index
          )

        residual_query =
          queries
          |> List.delete_at(index)
          |> PositionQuery.all()
          |> PositionQueryNormalizer.normalize()

        {
          :ok,
          structures,
          residual_query
        }
    end
  end

  defp edit_neighborhood_scan(_query) do
    :none
  end

  defp edit_neighborhood_node?({:pawn_structure_edit_neighborhood, [_structure | _remaining]}) do
    true
  end

  defp edit_neighborhood_node?(_query) do
    false
  end

  defp compile_edit_neighborhood_first(structures, residual_query, limit) do
    with {
           :ok,
           white_parameter,
           black_parameter,
           residual_predicate,
           parameters,
           next_parameter
         } <-
           compile_edit_neighborhood_components(
             structures,
             residual_query,
             1
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
        p.id
      FROM unnest(
        $#{white_parameter}::bigint[],
        $#{black_parameter}::bigint[]
      ) AS pawn_structure_keys(
        white_pawns,
        black_pawns
      )
      JOIN positions AS p
        ON p.white_pawns = pawn_structure_keys.white_pawns
        AND p.black_pawns = pawn_structure_keys.black_pawns
      WHERE
        (#{residual_predicate})
      ORDER BY
        p.id
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

  defp compile_edit_neighborhood_next(
         structures,
         residual_query,
         maximum_position_id,
         last_position_id,
         limit
       ) do
    with {
           :ok,
           white_parameter,
           black_parameter,
           residual_predicate,
           parameters,
           next_parameter
         } <-
           compile_edit_neighborhood_components(
             structures,
             residual_query,
             1
           ) do
      maximum_parameter =
        next_parameter

      last_parameter =
        maximum_parameter + 1

      limit_parameter =
        last_parameter + 1

      sql = """
      SELECT
        $#{maximum_parameter}::bigint AS maximum_position_id,
        p.id
      FROM unnest(
        $#{white_parameter}::bigint[],
        $#{black_parameter}::bigint[]
      ) AS pawn_structure_keys(
        white_pawns,
        black_pawns
      )
      JOIN positions AS p
        ON p.white_pawns = pawn_structure_keys.white_pawns
        AND p.black_pawns = pawn_structure_keys.black_pawns
      WHERE
        p.id > $#{last_parameter}::bigint
        AND p.id <= $#{maximum_parameter}::bigint
        AND (#{residual_predicate})
      ORDER BY
        p.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_position_id,
            last_position_id,
            limit
          ]
      }
    end
  end

  defp compile_edit_neighborhood_components(structures, residual_query, next_parameter) do
    white_parameter =
      next_parameter

    black_parameter =
      white_parameter + 1

    with {:ok,
          {
            white_pawns,
            black_pawns
          }} <-
           structures
           |> Enum.uniq()
           |> PositionPawnStructureCodec.encode_many(),
         {
           :ok,
           residual_predicate,
           residual_parameters,
           next_parameter
         } <-
           PredicateCompiler.compile_predicate(
             residual_query,
             black_parameter + 1
           ) do
      {
        :ok,
        white_parameter,
        black_parameter,
        residual_predicate,
        [
          white_pawns,
          black_pawns
        ] ++
          residual_parameters,
        next_parameter
      }
    end
  end

  defp symmetry_scan({:pawn_structures, [_structure | _remaining] = structures}) do
    {
      :ok,
      structures,
      true
    }
  end

  defp symmetry_scan({:and, queries}) do
    case Enum.find_index(
           queries,
           &symmetry_node?/1
         ) do
      nil ->
        :none

      index ->
        {
          :pawn_structures,
          structures
        } =
          Enum.at(
            queries,
            index
          )

        residual_query =
          queries
          |> List.delete_at(index)
          |> PositionQuery.all()
          |> PositionQueryNormalizer.normalize()

        {
          :ok,
          structures,
          residual_query
        }
    end
  end

  defp symmetry_scan(_query) do
    :none
  end

  defp symmetry_node?({:pawn_structures, [_structure | _remaining]}) do
    true
  end

  defp symmetry_node?(_query) do
    false
  end

  defp compile_symmetry_first(structures, residual_query, limit) do
    with {
           :ok,
           key_parameters,
           residual_predicate,
           parameters,
           next_parameter
         } <-
           compile_symmetry_components(
             structures,
             residual_query,
             1
           ) do
      limit_parameter =
        next_parameter

      branches =
        compile_symmetry_branches(
          key_parameters,
          residual_predicate,
          :first
        )

      sql = """
      SELECT
        COALESCE(
          (
            SELECT max(id)
            FROM positions
          ),
          0
        )::bigint AS maximum_position_id,
        matches.id
      FROM (
        #{branches}
      ) AS matches
      ORDER BY
        matches.id
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

  defp compile_symmetry_next(
         structures,
         residual_query,
         maximum_position_id,
         last_position_id,
         limit
       ) do
    with {
           :ok,
           key_parameters,
           residual_predicate,
           parameters,
           next_parameter
         } <-
           compile_symmetry_components(
             structures,
             residual_query,
             1
           ) do
      maximum_parameter =
        next_parameter

      last_parameter =
        maximum_parameter + 1

      limit_parameter =
        last_parameter + 1

      branches =
        compile_symmetry_branches(
          key_parameters,
          residual_predicate,
          {
            :next,
            maximum_parameter,
            last_parameter
          }
        )

      sql = """
      SELECT
        $#{maximum_parameter}::bigint AS maximum_position_id,
        matches.id
      FROM (
        #{branches}
      ) AS matches
      ORDER BY
        matches.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_position_id,
            last_position_id,
            limit
          ]
      }
    end
  end

  defp compile_symmetry_components(structures, residual_query, next_parameter) do
    with {:ok, encoded_structures} <-
           encode_structures(structures) do
      {
        key_parameters,
        next_parameter
      } =
        Enum.map_reduce(
          encoded_structures,
          next_parameter,
          fn
            _encoded_structure, next_parameter ->
              {
                {
                  next_parameter,
                  next_parameter + 1
                },
                next_parameter + 2
              }
          end
        )

      structure_parameters =
        Enum.flat_map(
          encoded_structures,
          fn
            {
              white_pawns,
              black_pawns
            } ->
              [
                white_pawns,
                black_pawns
              ]
          end
        )

      with {
             :ok,
             residual_predicate,
             residual_parameters,
             next_parameter
           } <-
             PredicateCompiler.compile_predicate(
               residual_query,
               next_parameter
             ) do
        {
          :ok,
          key_parameters,
          residual_predicate,
          structure_parameters ++
            residual_parameters,
          next_parameter
        }
      end
    end
  end

  defp encode_structures(structures) do
    structures
    |> Enum.uniq()
    |> Enum.reduce_while(
      {
        :ok,
        []
      },
      fn
        structure,
        {
          :ok,
          encoded_structures
        } ->
          case PositionPawnStructureCodec.encode(structure) do
            {:ok, encoded_structure} ->
              {:cont,
               {
                 :ok,
                 [
                   encoded_structure
                   | encoded_structures
                 ]
               }}

            {:error, reason} ->
              {:halt,
               {
                 :error,
                 reason
               }}
          end
      end
    )
    |> case do
      {
        :ok,
        encoded_structures
      } ->
        {:ok,
         encoded_structures
         |> Enum.reverse()
         |> Enum.uniq()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compile_symmetry_branches(key_parameters, residual_predicate, paging) do
    Enum.map_join(
      key_parameters,
      "\n\nUNION ALL\n\n",
      fn
        {
          white_parameter,
          black_parameter
        } ->
          compile_symmetry_branch(
            white_parameter,
            black_parameter,
            residual_predicate,
            paging
          )
      end
    )
  end

  defp compile_symmetry_branch(white_parameter, black_parameter, residual_predicate, paging) do
    conditions =
      [
        "p.white_pawns = $#{white_parameter}::bigint",
        "p.black_pawns = $#{black_parameter}::bigint"
      ] ++
        paging_conditions(paging) ++
        residual_conditions(residual_predicate)

    """
    (
      SELECT
        p.id
      FROM positions AS p
      WHERE
        #{Enum.join(conditions, "\n        AND ")}
      ORDER BY
        p.id
    )
    """
  end

  defp paging_conditions(:first) do
    []
  end

  defp paging_conditions({:next, maximum_parameter, last_parameter}) do
    [
      "p.id > $#{last_parameter}::bigint",
      "p.id <= $#{maximum_parameter}::bigint"
    ]
  end

  defp residual_conditions("TRUE") do
    []
  end

  defp residual_conditions(predicate) do
    [
      "(#{String.trim(predicate)})"
    ]
  end

  defp compile_generic_first(query, limit) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           PredicateCompiler.compile_predicate(
             query,
             1
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
        p.id
      FROM positions AS p
      WHERE
        (#{predicate})
      ORDER BY
        p.id
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

  defp compile_generic_next(query, maximum_position_id, last_position_id, limit) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           PredicateCompiler.compile_predicate(
             query,
             1
           ) do
      maximum_parameter =
        next_parameter

      last_parameter =
        maximum_parameter + 1

      limit_parameter =
        last_parameter + 1

      sql = """
      SELECT
        $#{maximum_parameter}::bigint,
        p.id
      FROM positions AS p
      WHERE
        p.id > $#{last_parameter}::bigint
        AND p.id <= $#{maximum_parameter}::bigint
        AND (#{predicate})
      ORDER BY
        p.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_position_id,
            last_position_id,
            limit
          ]
      }
    end
  end
end
