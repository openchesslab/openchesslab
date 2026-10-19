defmodule Analysis.GameSearch.PostgresQuery do
  @moduledoc false

  alias Analysis.FeatureDigest
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordQuery.Postgres, as: GameRecordPostgres
  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.Postgres, as: PositionPostgres
  alias Analysis.PositionQueryNormalizer

  @type compile_result ::
          {:ok, String.t(), [term()]}
          | {:error, term()}

  @spec compile_first(
          PositionQuery.t(),
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          compile_result()
  def compile_first(position_query, record_query, limit) when is_integer(limit) and limit > 0 do
    normalized_position_query =
      PositionQueryNormalizer.normalize(position_query)

    case edit_neighborhood_scan(normalized_position_query) do
      {
        :ok,
        structures,
        residual_query
      } ->
        compile_edit_neighborhood_first(
          structures,
          residual_query,
          record_query,
          limit
        )

      :none ->
        case symmetry_scan(normalized_position_query) do
          {
            :ok,
            structures,
            residual_query
          } ->
            compile_symmetry_first(
              structures,
              residual_query,
              record_query,
              limit
            )

          :none ->
            compile_generic_first(
              normalized_position_query,
              record_query,
              limit
            )
        end
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
          compile_result()
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
    normalized_position_query =
      PositionQueryNormalizer.normalize(position_query)

    case edit_neighborhood_scan(normalized_position_query) do
      {
        :ok,
        structures,
        residual_query
      } ->
        compile_edit_neighborhood_next(
          structures,
          residual_query,
          record_query,
          maximum_position_id,
          maximum_occurrence_id,
          maximum_record_row_id,
          last_position_id,
          last_occurrence_id,
          last_record_row_id,
          limit
        )

      :none ->
        case symmetry_scan(normalized_position_query) do
          {
            :ok,
            structures,
            residual_query
          } ->
            compile_symmetry_next(
              structures,
              residual_query,
              record_query,
              maximum_position_id,
              maximum_occurrence_id,
              maximum_record_row_id,
              last_position_id,
              last_occurrence_id,
              last_record_row_id,
              limit
            )

          :none ->
            compile_generic_next(
              normalized_position_query,
              record_query,
              maximum_position_id,
              maximum_occurrence_id,
              maximum_record_row_id,
              last_position_id,
              last_occurrence_id,
              last_record_row_id,
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

  defp compile_edit_neighborhood_first(structures, residual_query, record_query, limit) do
    with {
           :ok,
           white_parameter,
           black_parameter,
           residual_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_edit_neighborhood_components(
             structures,
             residual_query,
             record_query,
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
      JOIN game_occurrences AS go
        ON go.position_id = p.id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
      WHERE
        (#{residual_predicate})
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

  defp compile_edit_neighborhood_next(
         structures,
         residual_query,
         record_query,
         maximum_position_id,
         maximum_occurrence_id,
         maximum_record_row_id,
         last_position_id,
         last_occurrence_id,
         last_record_row_id,
         limit
       ) do
    with {
           :ok,
           white_parameter,
           black_parameter,
           residual_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_edit_neighborhood_components(
             structures,
             residual_query,
             record_query,
             1
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
      JOIN game_occurrences AS go
        ON go.position_id = p.id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
      WHERE
        p.id >= $#{last_position_parameter}::bigint
        AND p.id <= $#{maximum_position_parameter}::bigint
        AND go.id <= $#{maximum_occurrence_parameter}::bigint
        AND gr.id <= $#{maximum_record_parameter}::bigint
        AND (
          go.position_id,
          go.id
        ) >= (
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint
        )
        AND (
          go.position_id,
          go.id,
          gr.id
        ) > (
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint,
          $#{last_record_parameter}::bigint
        )
        AND (#{residual_predicate})
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

  defp compile_edit_neighborhood_components(
         structures,
         residual_query,
         record_query,
         next_parameter
       ) do
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
           record_predicate,
           predicate_parameters,
           next_parameter
         } <-
           compile_predicates(
             residual_query,
             record_query,
             black_parameter + 1
           ) do
      {
        :ok,
        white_parameter,
        black_parameter,
        residual_predicate,
        record_predicate,
        [
          white_pawns,
          black_pawns
        ] ++
          predicate_parameters,
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

  defp compile_symmetry_first(structures, residual_query, record_query, limit) do
    with {
           :ok,
           key_parameters,
           residual_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_symmetry_components(
             structures,
             residual_query,
             record_query,
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
        matches.id,
        go.id,
        go.game_id,
        go.ply,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata
      FROM (
        #{branches}
      ) AS matches
      JOIN game_occurrences AS go
        ON go.position_id = matches.id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
      WHERE
        (#{record_predicate})
      ORDER BY
        matches.id,
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

  defp compile_symmetry_next(
         structures,
         residual_query,
         record_query,
         maximum_position_id,
         maximum_occurrence_id,
         maximum_record_row_id,
         last_position_id,
         last_occurrence_id,
         last_record_row_id,
         limit
       ) do
    with {
           :ok,
           key_parameters,
           residual_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_symmetry_components(
             structures,
             residual_query,
             record_query,
             1
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

      branches =
        compile_symmetry_branches(
          key_parameters,
          residual_predicate,
          {
            :next,
            maximum_position_parameter,
            last_position_parameter
          }
        )

      sql = """
      SELECT
        $#{maximum_position_parameter}::bigint,
        $#{maximum_occurrence_parameter}::bigint,
        $#{maximum_record_parameter}::bigint,
        matches.id,
        go.id,
        go.game_id,
        go.ply,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata
      FROM (
        #{branches}
      ) AS matches
      JOIN game_occurrences AS go
        ON go.position_id = matches.id
      JOIN game_records AS gr
        ON gr.game_id = go.game_id
      WHERE
        go.position_id <= $#{maximum_position_parameter}::bigint
        AND go.id <= $#{maximum_occurrence_parameter}::bigint
        AND gr.id <= $#{maximum_record_parameter}::bigint
        AND (
          go.position_id,
          go.id
        ) >= (
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint
        )
        AND (
          go.position_id,
          go.id,
          gr.id
        ) > (
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint,
          $#{last_record_parameter}::bigint
        )
        AND (#{record_predicate})
      ORDER BY
        matches.id,
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

  defp compile_symmetry_components(structures, residual_query, record_query, next_parameter) do
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
             record_predicate,
             predicate_parameters,
             next_parameter
           } <-
             compile_predicates(
               residual_query,
               record_query,
               next_parameter
             ) do
        {
          :ok,
          key_parameters,
          residual_predicate,
          record_predicate,
          structure_parameters ++
            predicate_parameters,
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

  # Game-search paging may stop between records belonging to the
  # same position. Keep the cursor position in the ordered source;
  # the compound occurrence/record keyset below removes rows that
  # are not strictly after the cursor.
  defp paging_conditions({:next, maximum_position_parameter, last_position_parameter}) do
    [
      "p.id >= $#{last_position_parameter}::bigint",
      "p.id <= $#{maximum_position_parameter}::bigint"
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

  defp compile_generic_first(position_query, record_query, limit) do
    with {
           :ok,
           position_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_predicates(
             position_query,
             record_query,
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

  defp compile_generic_next(
         position_query,
         record_query,
         maximum_position_id,
         maximum_occurrence_id,
         maximum_record_row_id,
         last_position_id,
         last_occurrence_id,
         last_record_row_id,
         limit
       ) do
    with {
           :ok,
           position_predicate,
           record_predicate,
           parameters,
           next_parameter
         } <-
           compile_predicates(
             position_query,
             record_query,
             1
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
        go.position_id <= $#{maximum_position_parameter}::bigint
        AND go.id <= $#{maximum_occurrence_parameter}::bigint
        AND gr.id <= $#{maximum_record_parameter}::bigint
        AND (
          go.position_id,
          go.id
        ) >= (
          $#{last_position_parameter}::bigint,
          $#{last_occurrence_parameter}::bigint
        )
        AND (
          go.position_id,
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

  # The pawn skeleton within one structural edit, encoded for the
  # positions-column unnest join.
  defp encode_neighborhood(position) do
    {:pawn_structure_edit_neighborhood, structures} =
      PositionQuery.pawn_structure_edit_neighborhood(position, 1)

    PositionPawnStructureCodec.encode_many(structures)
  end

  # Atoms register on first sight; the dictionary hands out stable ids.
  defp resolve_atom_ids(atoms) do
    {:ok, FeatureDigest.ids_for(atoms)}
  end

  defp similar_keyset(nil, atoms_parameter) do
    maximum_parameters = %{
      position: atoms_parameter + 1,
      occurrence: atoms_parameter + 2,
      record: atoms_parameter + 3
    }

    {maximum_parameters, [], []}
  end

  defp similar_keyset(%Analysis.GameSearch.Cursor{} = cursor, atoms_parameter) do
    maximum_parameters = %{
      position: atoms_parameter + 1,
      occurrence: atoms_parameter + 2,
      record: atoms_parameter + 3
    }

    last_shared_parameter = atoms_parameter + 4
    last_position_parameter = atoms_parameter + 5
    last_occurrence_parameter = atoms_parameter + 6
    last_record_parameter = atoms_parameter + 7

    conditions = [
      "go.position_id <= $#{maximum_parameters.position}::bigint",
      "go.id <= $#{maximum_parameters.occurrence}::bigint",
      "gr.id <= $#{maximum_parameters.record}::bigint",
      "(
        cardinality(pd.atom_ids & $#{atoms_parameter}::integer[]),
        p.id,
        go.id,
        gr.id
      ) < (
        $#{last_shared_parameter}::bigint,
        $#{last_position_parameter}::bigint,
        $#{last_occurrence_parameter}::bigint,
        $#{last_record_parameter}::bigint
      )"
    ]

    parameters = [
      cursor.maximum_position_id,
      cursor.maximum_occurrence_id,
      cursor.maximum_record_row_id,
      cursor.last_shared,
      cursor.last_position_id,
      cursor.last_occurrence_id,
      cursor.last_record_row_id
    ]

    {maximum_parameters, conditions, parameters}
  end

  defp similar_sql(
         record_predicate,
         signature_parameter,
         atoms_parameter,
         maximum_parameters,
         keyset_conditions,
         limit_parameter
       ) do
    maximum_select =
      if keyset_conditions == [] do
        """
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
        """
      else
        """
          $#{maximum_parameters.position}::bigint AS maximum_position_id,
          $#{maximum_parameters.occurrence}::bigint AS maximum_occurrence_id,
          $#{maximum_parameters.record}::bigint AS maximum_record_row_id
        """
      end

    keyset_where =
      case keyset_conditions do
        [] ->
          ""

        conditions ->
          conditions
          |> Enum.map_join("", fn condition -> "\n  AND #{condition}\n" end)
      end

    """
    SELECT
      #{maximum_select},
      cardinality(pd.atom_ids & $#{atoms_parameter}::integer[]) AS shared,
      p.id,
      go.id,
      go.game_id,
      go.ply,
      gr.id,
      gr.record_id,
      gr.game_id,
      gr.fullmove_number,
      gr.metadata
    FROM unnest(
      $1::bigint[],
      $2::bigint[]
    ) AS pawn_structure_keys(
      white_pawns,
      black_pawns
    )
    JOIN positions AS p
      ON p.white_pawns = pawn_structure_keys.white_pawns
      AND p.black_pawns = pawn_structure_keys.black_pawns
    JOIN position_digests AS pd
      ON pd.position_id = p.id
    JOIN game_occurrences AS go
      ON go.position_id = p.id
    JOIN game_records AS gr
      ON gr.game_id = go.game_id
    WHERE
      pd.atom_ids @> $#{signature_parameter}::integer[]
      AND (#{record_predicate})#{keyset_where}
    ORDER BY
      shared DESC,
      p.id,
      go.id,
      gr.id
    LIMIT $#{limit_parameter}::bigint
    """
  end

  # The record-driven newest-first page for game-only searches: one row per
  # record, the first occurrence (lowest ply) joined for the preview. The
  # (coalesced date, id) keyset matches the game_records_date_id_index.
  @spec compile_similar(
          Chess.Position.t(),
          [String.t()],
          [String.t()],
          GameRecordQuery.t(),
          Analysis.GameSearch.Cursor.t() | nil,
          pos_integer()
        ) ::
          compile_result()
  def compile_similar(position, signatures, atoms, record_query, cursor, limit)
      when is_integer(limit) and limit > 0 do
    with {:ok, {white_pawns, black_pawns}} <-
           encode_neighborhood(position),
         {:ok, signature_ids} <- resolve_atom_ids(signatures),
         {:ok, atom_ids} <- resolve_atom_ids(atoms),
         {:ok, record_predicate, record_parameters, next_parameter} <-
           GameRecordPostgres.compile_predicate(
             record_query,
             3
           ) do
      signature_parameter = next_parameter
      atoms_parameter = signature_parameter + 1

      {maximum_parameters, keyset_conditions, keyset_parameters} =
        similar_keyset(cursor, atoms_parameter)

      limit_parameter = atoms_parameter + 1 + length(keyset_parameters)

      sql =
        similar_sql(
          record_predicate,
          signature_parameter,
          atoms_parameter,
          maximum_parameters,
          keyset_conditions,
          limit_parameter
        )

      parameters =
        [
          white_pawns,
          black_pawns
        ] ++
          record_parameters ++
          [signature_ids, atom_ids] ++
          keyset_parameters ++
          [limit]

      {
        :ok,
        sql,
        parameters
      }
    end
  end

  @spec compile_date_first(
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          compile_result()
  def compile_date_first(record_query, limit) when is_integer(limit) and limit > 0 do
    with {
           :ok,
           record_predicate,
           parameters,
           next_parameter
         } <-
           GameRecordPostgres.compile_predicate(
             record_query,
             1
           ) do
      limit_parameter =
        next_parameter

      sql = """
      SELECT
        COALESCE(
          (
            SELECT max(id)
            FROM game_records
          ),
          0
        )::bigint AS maximum_record_row_id,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata,
        go.id,
        go.ply,
        go.position_id
      FROM game_records AS gr
      LEFT JOIN LATERAL (
        SELECT
          id,
          ply,
          position_id
        FROM game_occurrences
        WHERE game_id = gr.game_id
        ORDER BY ply
        LIMIT 1
      ) AS go
        ON TRUE
      WHERE
        (#{record_predicate})
      ORDER BY
        COALESCE(gr.metadata ->> 'date', '') DESC,
        gr.id DESC
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

  @spec compile_date_next(
          GameRecordQuery.t(),
          non_neg_integer(),
          String.t(),
          pos_integer(),
          pos_integer()
        ) ::
          compile_result()
  def compile_date_next(record_query, maximum_record_row_id, last_date, last_record_row_id, limit)
      when is_integer(maximum_record_row_id) and maximum_record_row_id >= 0 and
             is_binary(last_date) and is_integer(last_record_row_id) and last_record_row_id > 0 and
             is_integer(limit) and limit > 0 do
    with {
           :ok,
           record_predicate,
           parameters,
           next_parameter
         } <-
           GameRecordPostgres.compile_predicate(
             record_query,
             1
           ) do
      maximum_parameter =
        next_parameter

      last_date_parameter =
        maximum_parameter + 1

      last_record_parameter =
        last_date_parameter + 1

      limit_parameter =
        last_record_parameter + 1

      sql = """
      SELECT
        $#{maximum_parameter}::bigint AS maximum_record_row_id,
        gr.id,
        gr.record_id,
        gr.game_id,
        gr.fullmove_number,
        gr.metadata,
        go.id,
        go.ply,
        go.position_id
      FROM game_records AS gr
      LEFT JOIN LATERAL (
        SELECT
          id,
          ply,
          position_id
        FROM game_occurrences
        WHERE game_id = gr.game_id
        ORDER BY ply
        LIMIT 1
      ) AS go
        ON TRUE
      WHERE
        gr.id <= $#{maximum_parameter}::bigint
        AND (
          COALESCE(gr.metadata ->> 'date', ''),
          gr.id
        ) < (
          $#{last_date_parameter}::text,
          $#{last_record_parameter}::bigint
        )
        AND (#{record_predicate})
      ORDER BY
        COALESCE(gr.metadata ->> 'date', '') DESC,
        gr.id DESC
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_record_row_id,
            last_date,
            last_record_row_id,
            limit
          ]
      }
    end
  end

  defp compile_predicates(position_query, record_query, next_parameter) do
    with {
           :ok,
           position_predicate,
           position_parameters,
           next_parameter
         } <-
           PositionPostgres.compile_predicate(
             position_query,
             next_parameter
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
