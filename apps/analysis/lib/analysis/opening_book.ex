defmodule Analysis.OpeningBook do
  @moduledoc """
  The opening book: ECO classification plus corpus move statistics.

  Classification uses the CC0 lichess-org/chess-openings dataset, seeded into
  the `openings` table keyed by the canonical position encoding. Corpus stats
  aggregate `game_occurrences.move`: which moves were played from a position,
  with per-result counts from the records' metadata. Everything is local —
  no external fetches.
  """

  alias Analysis.PositionStore
  alias Chess.Notation.SAN
  alias Chess.Notation.UCI
  alias Chess.Position
  alias Chess.PositionCodec
  alias OpenChessLab.Repo

  @classify_sql """
  SELECT eco, name
  FROM openings
  WHERE position_record = $1
  """

  # Totals count distinct games; W/D/L counts distinct records (each imported
  # game record carries its result).
  @moves_sql """
  SELECT
    o.move,
    count(DISTINCT o.game_id),
    count(DISTINCT gr.id) FILTER (WHERE gr.metadata ->> 'result' = '1-0'),
    count(DISTINCT gr.id) FILTER (WHERE gr.metadata ->> 'result' = '1/2-1/2'),
    count(DISTINCT gr.id) FILTER (WHERE gr.metadata ->> 'result' = '0-1')
  FROM game_occurrences o
  JOIN game_records gr ON gr.game_id = o.game_id
  WHERE o.position_id = $1 AND o.move IS NOT NULL
  GROUP BY o.move
  ORDER BY count(DISTINCT o.game_id) DESC, o.move
  LIMIT $2
  """

  @type classification :: %{eco: String.t(), name: String.t()}

  @doc "The ECO classification of an exact position, if the dataset names it."
  @spec classify(Position.t()) :: {:ok, classification()} | :not_found
  def classify(%Position{} = position) do
    record = PositionCodec.encode(position)

    case Repo.query!(@classify_sql, [record], log: false).rows do
      [[eco, name]] -> {:ok, %{eco: eco, name: name}}
      [] -> :not_found
    end
  end

  @doc """
  The classification of a line: the deepest named position from the root to
  the current path (the recommended way to classify games — it keeps working
  through transpositions and unnamed mid-line positions).
  """
  @spec classify_line(Analysis.Analysis.t(), Analysis.Analysis.path()) ::
          {:ok, classification()} | :not_found
  def classify_line(%Analysis.Analysis{} = analysis, path) when is_list(path) do
    nodes =
      for length <- 0..length(path),
          node = Analysis.Analysis.node_at(analysis, Enum.take(path, length)),
          not is_nil(node),
          do: node

    positions =
      nodes
      |> Enum.map(&Analysis.Node.position_id/1)
      |> PositionStore.get_many()

    nodes
    |> Enum.reduce(:not_found, fn node, acc ->
      case Map.get(positions, Analysis.Node.position_id(node)) do
        %Position{} = position ->
          case classify(position) do
            {:ok, classification} -> {:ok, classification}
            :not_found -> acc
          end

        _ ->
          acc
      end
    end)
  end

  @doc """
  Moves played from the position in the stored corpus, most played first.

  Each entry carries the SAN label, the number of distinct games playing it,
  per-result record counts, and the opening it leads to when classified.
  """
  @spec moves(Position.t(), integer(), keyword()) :: [map()]
  def moves(%Position{} = position, position_id, options \\ []) do
    limit = Keyword.get(options, :limit, 50)

    @moves_sql
    |> Repo.query!([position_id, limit], log: false)
    |> Map.get(:rows)
    |> Enum.map(fn [uci, games, white, draws, black] ->
      with {:ok, move} <- UCI.parse_move(position, uci),
           {:ok, san} <- SAN.format(position, move),
           {:ok, next} <- Position.apply_move(position, move) do
        %{
          uci: uci,
          san: san,
          games: games,
          white: white,
          draws: draws,
          black: black,
          opening: classify_opening_after(next)
        }
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp classify_opening_after(position) do
    case classify(position) do
      {:ok, classification} -> classification
      :not_found -> nil
    end
  end
end
