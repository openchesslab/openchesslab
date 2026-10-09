defmodule Features do
  @moduledoc """
  Extracts features of chess positions and games as described in
  `docs/POSITION_FEATURES.md`.

  The public API is built around `Features.extract/2`, which takes a
  position (FEN string or `Features.Chess.Board`) and returns a
  versioned `Features.Result` populated by the feature catalogue.
  """

  alias Features.Catalogue
  alias Features.Catalogue.{AttackMap, Evaluation, Similarity}
  alias Features.Chess.{Board, FEN}
  alias Features.Result

  @version "0.1.0"

  @doc "Schema version of extracted feature results."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Compute every catalogue feature for `position` (a FEN string or a
  `Features.Chess.Board`). Options:

    * `:sections` — only extract the given spec sections (e.g. `[2]`).
    * `:reference` — the position (FEN string or board) whose relation
      to `position` fills the section 21 similarity features; defaults
      to the starting position.
  """
  @spec extract(String.t() | Board.t(), keyword()) :: Result.t()
  def extract(position, opts \\ []) do
    sections = Keyword.get(opts, :sections)
    board = to_workspace(position, sections)

    features =
      Catalogue.all()
      |> maybe_sections(sections)
      |> Map.new(fn feature -> {feature.id, feature.compute.(board)} end)

    features =
      case Keyword.get(opts, :reference) do
        nil ->
          features

        reference ->
          if sections == nil or 21 in sections do
            Map.merge(features, Similarity.compare(reference, board))
          else
            features
          end
      end

    %Result{version: version(), fen: FEN.to_fen(board), features: features}
  end

  @doc """
  Compare `reference` and `position` against every section 21 similarity
  feature, returning a `%{"similarity.*" => value}` map.
  """
  @spec compare(String.t() | Board.t(), String.t() | Board.t()) :: %{String.t() => term()}
  def compare(reference, position), do: Similarity.compare(reference, position)

  defp maybe_sections(features, nil), do: features
  defp maybe_sections(features, sections), do: Enum.filter(features, &(&1.section in sections))

  @spec to_cached_board(String.t() | Board.t()) :: Board.t()
  defp to_cached_board(%Board{} = board), do: %{board | attack_table: AttackMap.build(board)}
  defp to_cached_board(fen) when is_binary(fen), do: to_cached_board(FEN.parse(fen))

  @spec to_workspace(String.t() | Board.t(), keyword() | nil) :: Board.t()
  defp to_workspace(position, sections) do
    %Board{} = board = to_cached_board(position)

    board =
      if sections == nil or 20 in sections do
        %{board | evaluation_cache: Evaluation.workspace(board)}
      else
        board
      end

    if sections == nil or 21 in sections do
      %{board | similarity_cache: Similarity.digests(board)}
    else
      board
    end
  end
end
