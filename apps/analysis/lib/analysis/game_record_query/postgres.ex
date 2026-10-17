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

  def compile_predicate({:metadata_value_contains, key, substring}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {
      :ok,
      "gr.metadata ->> $#{next_parameter} ILIKE $#{next_parameter + 1} ESCAPE '\\'",
      [
        key,
        "%" <> escape_like(substring) <> "%"
      ],
      next_parameter + 2
    }
  end

  def compile_predicate({:metadata_value_between, _key, nil, nil}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {:ok, "TRUE", [], next_parameter}
  end

  def compile_predicate({:metadata_int_between, _key, nil, nil}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {:ok, "TRUE", [], next_parameter}
  end

  def compile_predicate({:metadata_value_between, key, minimum, maximum}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {clauses, params, next} =
      between_clauses(
        "(gr.metadata ->> $#{next_parameter})",
        minimum,
        maximum,
        next_parameter + 1
      )

    compile_between(clauses, [key | params], next)
  end

  def compile_predicate({:metadata_int_between, key, minimum, maximum}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    # The guard keeps non-numeric values ("?", "-") out of the integer cast.
    guard = "(gr.metadata ->> $#{next_parameter}) ~ '^[0-9]+$'"

    {clauses, params, next} =
      between_clauses(
        "(gr.metadata ->> $#{next_parameter})::int",
        minimum,
        maximum,
        next_parameter + 1
      )

    case clauses do
      [] -> {:ok, "TRUE", [], next}
      _ -> {:ok, Enum.join([guard | clauses], " AND "), [key | params], next}
    end
  end

  def compile_predicate({:and, queries}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0,
      do: compile_junction("AND", queries, "TRUE", next_parameter)

  def compile_predicate({:or, queries}, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0,
      do: compile_junction("OR", queries, "FALSE", next_parameter)

  def compile_predicate(_query, next_parameter)
      when is_integer(next_parameter) and next_parameter > 0 do
    {:error, :unsupported_game_record_query}
  end

  defp compile_junction(_operator, [], empty_sql, next_parameter) do
    {:ok, empty_sql, [], next_parameter}
  end

  defp compile_junction(operator, queries, _empty_sql, next_parameter) do
    queries
    |> Enum.reduce_while({[], [], next_parameter}, fn query, {parts, params, next} ->
      case compile_predicate(query, next) do
        {:ok, sql, query_params, advanced} ->
          {:cont, {["(#{sql})" | parts], params ++ query_params, advanced}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:error, _reason} = error ->
        error

      {parts, params, advanced} ->
        {:ok, parts |> Enum.reverse() |> Enum.join(" #{operator} "), params, advanced}
    end
  end

  # One ">= $n" / "<= $n" clause per present bound; nil bounds stay open.
  # `column` is the already-parameterised value expression (the key sits in
  # the parameter slot it was built from).
  defp between_clauses(_column, nil, nil, next_parameter), do: {[], [], next_parameter}

  defp between_clauses(column, minimum, maximum, next_parameter) do
    {clauses, params, next} =
      if minimum do
        {["#{column} >= $#{next_parameter}"], [minimum], next_parameter + 1}
      else
        {[], [], next_parameter}
      end

    if maximum do
      {clauses ++ ["#{column} <= $#{next}"], params ++ [maximum], next + 1}
    else
      {clauses, params, next}
    end
  end

  defp compile_between([], _params, next), do: {:ok, "TRUE", [], next}

  defp compile_between(clauses, params, next) do
    {:ok, Enum.join(clauses, " AND "), params, next}
  end

  # ILIKE treats % and _ as wildcards; search text must not.
  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
