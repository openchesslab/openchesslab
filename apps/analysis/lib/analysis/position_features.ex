defmodule Analysis.PositionFeatures do
  @moduledoc """
  Bridge between the analysis domain and the `Features` catalogue.

  Extracts the full feature vector for a position (from a
  `Chess.Position`, from a stored `Analysis.PositionStore` id, or from a
  node of an `Analysis.Analysis`) and persists the extracted vector per
  position in `position_feature_vectors`.

  Persistence is explicit: `store/1`, `store_position_id/1` and
  `backfill/0` write the vector; `fetch/1` reads it back and
  `fetch_or_extract/1` computes and stores it on first access.
  """

  import Bitwise

  alias Analysis.Analyses
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Chess.Board
  alias Chess.Position
  alias Features
  alias Features.Chess.Board, as: FeaturesBoard
  alias Features.Result, as: FeaturesResult
  alias OpenChessLab.Repo

  @type feature_result :: FeaturesResult.t()

  @castling_bits %{
    white_kingside: 1,
    white_queenside: 2,
    black_kingside: 4,
    black_queenside: 8
  }

  @type_names %{
    king: :kings,
    queen: :queens,
    rook: :rooks,
    bishop: :bishops,
    knight: :knights,
    pawn: :pawns
  }

  @upsert_sql """
  INSERT INTO position_feature_vectors (
    position_id,
    version,
    fen,
    features,
    inserted_at,
    updated_at
  )
  VALUES (
    $1,
    $2,
    $3,
    $4::jsonb,
    now(),
    now()
  )
  ON CONFLICT (position_id) DO UPDATE SET
    version = EXCLUDED.version,
    fen = EXCLUDED.fen,
    features = EXCLUDED.features,
    updated_at = now()
  """

  @fetch_sql """
  SELECT
    version,
    fen,
    features
  FROM position_feature_vectors
  WHERE position_id = $1
  """

  @all_position_ids_sql """
  SELECT id
  FROM positions
  ORDER BY id
  """

  @doc """
  Convert a `Chess.Position` into the equivalent `Features.Chess.Board`.
  """
  @spec from_position(Position.t()) :: FeaturesBoard.t()
  def from_position(%Position{} = position) do
    features_board =
      position.board
      |> Board.pieces()
      |> Enum.reduce(empty_pieces(), fn {square, {color, type}}, acc ->
        bit = 1 <<< square
        key = {color, Map.fetch!(@type_names, type)}
        Map.update!(acc, key, &(&1 ||| bit))
      end)

    FeaturesBoard.build(features_board,
      side_to_move: position.side_to_move,
      castling: castling_bits(position.castling_rights),
      en_passant: position.en_passant
    )
  end

  @doc """
  Extract the feature vector for a `Chess.Position`.
  """
  @spec extract(Position.t()) :: {:ok, feature_result()}
  def extract(%Position{} = position) do
    {:ok, Features.extract(from_position(position))}
  end

  @doc """
  Extract the feature vector for a stored position id.
  """
  @spec extract_position_id(PositionStore.position_id()) ::
          {:ok, feature_result()} | :not_found | {:error, term()}
  def extract_position_id(position_id) when is_integer(position_id) and position_id > 0 do
    case PositionStore.get(position_id) do
      {:ok, position} ->
        extract(position)

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract_position_id(_position_id) do
    :not_found
  end

  @doc """
  Extract the feature vector for the position at `path` in an analysis.
  """
  @spec extract_at(Analysis.Analysis.id(), Analysis.Analysis.path()) ::
          {:ok, feature_result()} | {:error, term()}
  def extract_at(analysis_id, path) do
    case Analyses.get(analysis_id) do
      {:ok, analysis, _revision} ->
        case Analysis.Analysis.node_at(analysis, path) do
          %Node{} = node ->
            extract_position_id(Node.position_id(node))

          nil ->
            {:error, :node_not_found}
        end

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @doc """
  Extract and persist the feature vector for a `Chess.Position`.
  """
  @spec store(Position.t()) :: {:ok, feature_result()} | {:error, term()}
  def store(%Position{} = position) do
    with {:ok, result} <- extract(position),
         {:ok, position_id} <- append_position(position) do
      store_result(position_id, result)
    end
  end

  @doc """
  Extract and persist the feature vector for a stored position id.
  """
  @spec store_position_id(PositionStore.position_id()) ::
          {:ok, feature_result()} | :not_found | {:error, term()}
  def store_position_id(position_id) do
    with {:ok, result} <- extract_position_id(position_id) do
      store_result(position_id, result)
    end
  end

  @doc """
  Read a persisted feature vector for a stored position id.
  """
  @spec fetch(PositionStore.position_id()) ::
          {:ok, feature_result()} | :not_found | {:error, term()}
  def fetch(position_id) when is_integer(position_id) and position_id > 0 do
    case Repo.query(@fetch_sql, [position_id]) do
      {:ok, %{rows: [[version, fen, features]]}} ->
        {:ok, build_result(version, fen, features)}

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_position_id) do
    :not_found
  end

  @doc """
  Read a persisted feature vector for a stored position id, computing
  and storing it on first access.
  """
  @spec fetch_or_extract(PositionStore.position_id()) ::
          {:ok, feature_result()} | {:error, term()}
  def fetch_or_extract(position_id) do
    case fetch(position_id) do
      {:ok, _result} = ok ->
        ok

      :not_found ->
        store_position_id(position_id)

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Persist feature vectors for every stored position that does not yet
  have one, returning the number of positions computed, already cached
  and failed.
  """
  @spec backfill() :: {:ok, map()} | {:error, term()}
  def backfill do
    case Repo.query(@all_position_ids_sql, []) do
      {:ok, %{rows: rows}} ->
        {:ok, do_backfill(Enum.map(rows, fn [position_id] -> position_id end))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_position(position) do
    case PositionStore.append(position) do
      position_id when is_integer(position_id) and position_id > 0 ->
        {:ok, position_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_result(position_id, result) do
    case Repo.query(
           @upsert_sql,
           [
             position_id,
             result.version,
             result.fen,
             Jason.encode!(result.features)
           ]
         ) do
      {:ok, _result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_result(version, fen, features) do
    %FeaturesResult{version: version, fen: fen, features: Jason.decode!(features)}
  end

  defp do_backfill(position_ids) do
    Enum.reduce(
      position_ids,
      %{computed: 0, cached: 0, failed: 0},
      fn position_id, stats ->
        case fetch(position_id) do
          {:ok, _result} ->
            %{stats | cached: stats.cached + 1}

          :not_found ->
            case store_position_id(position_id) do
              {:ok, _result} ->
                %{stats | computed: stats.computed + 1}

              {:error, _reason} ->
                %{stats | failed: stats.failed + 1}
            end

          {:error, _reason} ->
            %{stats | failed: stats.failed + 1}
        end
      end
    )
  end

  defp empty_pieces do
    for color <- FeaturesBoard.colors(), type <- FeaturesBoard.types(), into: %{} do
      {{color, type}, 0}
    end
  end

  defp castling_bits(rights) do
    MapSet.to_list(rights)
    |> Enum.reduce(0, fn right, acc -> acc + Map.fetch!(@castling_bits, right) end)
  end
end
