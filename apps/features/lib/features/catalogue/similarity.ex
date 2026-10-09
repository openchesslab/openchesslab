defmodule Features.Catalogue.Similarity do
  @moduledoc """
  Spec section 21 — similarity and structural relations with other
  positions.

  Unlike the earlier sections these features relate one position to
  another. A single extraction compares the position against a default
  reference (the starting position); use `Features.compare/2` or pass a
  `:reference` option to `Features.extract/2` to compare against any
  other position.
  """

  import Bitwise

  alias Features.Catalogue.Support
  alias Features.Chess.{Bitboard, Board, FEN, Square}
  alias Features.Feature

  @default_reference FEN.start_fen()

  @attack_digest_ids ~w(
    goals.kingside_attack goals.queenside_attack goals.central_attack goals.pawn_storm
    goals.transfer_pieces_to_kingside goals.transfer_pieces_to_queenside
  )

  @spec features() :: [Feature.t()]
  def features do
    reference = to_board(@default_reference)

    Enum.map(similarity_features(), fn {id, claim, fun} ->
      Feature.new(id, 21, [{21, claim}], fn board -> fun.(reference, to_board(board)) end)
    end)
  end

  @doc """
  Compare two positions against every similarity feature, returning a
  `%{"similarity.*" => value}` map.
  """
  @spec compare(String.t() | Board.t(), String.t() | Board.t()) :: %{String.t() => term()}
  def compare(reference, position) do
    a = to_board(reference)
    b = to_board(position)

    Map.new(similarity_features(), fn {id, _claim, fun} -> {id, fun.(a, b)} end)
  end

  defp similarity_features do
    [
      {"similarity.exact_same_position", "exact dezelfde positie", &exact_same_position?/2},
      {"similarity.same_position_other_side", "dezelfde positie met andere side to move",
       &same_position_other_side?/2},
      {"similarity.color_swapped_position", "kleurverwisselde positie",
       &color_swapped_position?/2},
      {"similarity.mirrored_position", "horizontaal/verticaal gespiegeld", &mirrored_position?/2},
      {"similarity.same_pawn_structure", "dezelfde pawn structure", &same_pawn_structure?/2},
      {"similarity.comparable_pawn_structure", "vergelijkbare pawn structure",
       &comparable_pawn_structure?/2},
      {"similarity.same_material_distribution", "dezelfde materiaalverdeling",
       &same_material_distribution?/2},
      {"similarity.comparable_material_distribution", "vergelijkbare materiaalverdeling",
       &comparable_material_distribution?/2},
      {"similarity.same_piece_placement_patterns", "dezelfde stukplaatsingspatronen",
       &same_piece_placement_patterns?/2},
      {"similarity.same_strategic_structure", "dezelfde strategische structuur",
       &same_strategic_structure?/2},
      {"similarity.same_king_safety_structure", "dezelfde king-safetystructuur",
       &same_king_safety_structure?/2},
      {"similarity.same_tactical_geometry", "dezelfde tactische geometrie",
       &same_tactical_geometry?/2},
      {"similarity.comparable_attack_plan", "vergelijkbaar aanvalsplan",
       &comparable_attack_plan?/2},
      {"similarity.structural_distance", "structurele afstand tussen posities",
       &structural_distance/2},
      {"similarity.pawn_edit_distance", "pawn-edit distance", &pawn_edit_distance/2},
      {"similarity.one_pawn_shifted", "één pion verschoven", &one_pawn_shifted?/2},
      {"similarity.bishop_knight_substitution", "bishop ↔ knight substitution",
       &bishop_knight_substitution?/2},
      {"similarity.two_rooks_queen_substitution", "twee rooks ↔ queen substitution",
       &two_rooks_queen_substitution?/2}
    ]
  end

  defp to_board(%Board{} = board), do: board
  defp to_board(fen) when is_binary(fen), do: FEN.parse(fen)

  defp exact_same_position?(a, b), do: position_key(a) == position_key(b)

  defp same_position_other_side?(a, b) do
    position_key(%{a | side_to_move: Board.opposite(a.side_to_move)}) == position_key(b)
  end

  defp color_swapped_position?(a, b), do: position_key(color_swapped(a)) == position_key(b)

  defp mirrored_position?(a, b) do
    position_key(mirror(a, :horizontal)) == position_key(b) or
      position_key(mirror(a, :vertical)) == position_key(b)
  end

  defp same_pawn_structure?(a, b), do: pawn_structure(a) == pawn_structure(b)

  defp comparable_pawn_structure?(a, b), do: pawn_edit_distance(a, b) <= 2

  defp same_material_distribution?(a, b) do
    Support.piece_counts(a, :white) == Support.piece_counts(b, :white) and
      Support.piece_counts(a, :black) == Support.piece_counts(b, :black)
  end

  defp comparable_material_distribution?(a, b) do
    abs(total_material(a) - total_material(b)) <= 2
  end

  defp same_piece_placement_patterns?(a, b) do
    Enum.all?([:knights, :bishops, :rooks, :queens, :kings], fn type ->
      same_piece_set?(a, b, type)
    end)
  end

  defp same_strategic_structure?(a, b),
    do: digest(a, [3, 4, 7, 9, 11]) == digest(b, [3, 4, 7, 9, 11])

  defp same_king_safety_structure?(a, b), do: digest(a, [11]) == digest(b, [11])
  defp same_tactical_geometry?(a, b), do: digest(a, [12]) == digest(b, [12])

  defp comparable_attack_plan?(a, b) do
    Features.extract(a, sections: [15]).features
    |> Map.take(@attack_digest_ids) ==
      Features.extract(b, sections: [15]).features |> Map.take(@attack_digest_ids)
  end

  defp structural_distance(a, b) do
    pawn_edit_distance(a, b) +
      placement_distance(a, b) +
      king_safety_distance(a, b) +
      material_distance(a, b)
  end

  defp pawn_edit_distance(a, b) do
    Enum.count(0..7, fn file ->
      mask = Support.file_bb(file)

      (pawn_bb(a, :white) &&& mask) != (pawn_bb(b, :white) &&& mask) or
        (pawn_bb(a, :black) &&& mask) != (pawn_bb(b, :black) &&& mask)
    end)
  end

  defp one_pawn_shifted?(a, b) do
    Enum.any?(Board.colors(), &one_color_pawn_shift?(a, b, &1))
  end

  defp bishop_knight_substitution?(a, b) do
    Enum.any?(Board.colors(), fn color ->
      delta_bishops =
        Support.piece_count(a, color, :bishops) - Support.piece_count(b, color, :bishops)

      delta_knights =
        Support.piece_count(a, color, :knights) - Support.piece_count(b, color, :knights)

      abs(delta_bishops) == 1 and delta_knights == -delta_bishops and
        pieces_equal_except?(a, b, [{color, :bishops}, {color, :knights}])
    end)
  end

  defp two_rooks_queen_substitution?(a, b) do
    Enum.any?(Board.colors(), fn color ->
      delta_rooks = Support.piece_count(a, color, :rooks) - Support.piece_count(b, color, :rooks)

      delta_queens =
        Support.piece_count(a, color, :queens) - Support.piece_count(b, color, :queens)

      abs(delta_rooks) == 2 and delta_queens == -div(delta_rooks, 2) and
        pieces_equal_except?(a, b, [{color, :rooks}, {color, :queens}])
    end)
  end

  defp position_key(board) do
    {Board.build(board.pieces).pieces, board.side_to_move, board.castling, board.en_passant}
  end

  defp pawn_structure(board) do
    %{"white" => pawn_bb(board, :white), "black" => pawn_bb(board, :black)}
  end

  defp pawn_bb(board, color), do: Board.piece_bb(board, color, :pawns)

  defp same_piece_set?(a, b, type) do
    Enum.all?(Board.colors(), fn color ->
      Board.piece_bb(a, color, type) == Board.piece_bb(b, color, type)
    end)
  end

  defp digest(board, sections), do: Features.extract(board, sections: sections).features

  defp placement_distance(a, b) do
    Enum.reduce(Board.colors(), 0, fn color, acc ->
      Enum.reduce([:knights, :bishops, :rooks, :queens, :kings], acc, fn type, acc ->
        acc +
          Support.popcount(
            Bitwise.bxor(Board.piece_bb(a, color, type), Board.piece_bb(b, color, type))
          )
      end)
    end)
  end

  defp king_safety_distance(a, b) do
    (same_piece_set?(a, b, :kings) && 0) || 1
  end

  defp material_distance(a, b), do: abs(total_material(a) - total_material(b))

  defp total_material(board) do
    Support.material_value(board, :white) + Support.material_value(board, :black)
  end

  defp one_color_pawn_shift?(a, b, color) do
    other = Board.opposite(color)

    pawn_bb(a, other) == pawn_bb(b, other) &&
      case {Bitboard.squares(pawn_bb(a, color) &&& bnot(pawn_bb(b, color))),
            Bitboard.squares(pawn_bb(b, color) &&& bnot(pawn_bb(a, color)))} do
        {[from], [to]} -> pawn_shift?(color, from, to)
        _ -> false
      end
  end

  defp pawn_shift?(color, from, to) do
    delta_rank = Square.rank(to) - Square.rank(from)
    delta_file = abs(Square.file(to) - Square.file(from))

    ((color == :white and delta_rank in [1, 2]) or (color == :black and delta_rank in [-1, -2])) and
      delta_file <= 1
  end

  defp pieces_equal_except?(a, b, except) do
    Enum.all?(Board.colors(), fn color ->
      Enum.all?(Board.types(), fn type ->
        {color, type} in except or
          Board.piece_bb(a, color, type) == Board.piece_bb(b, color, type)
      end)
    end)
  end

  defp color_swapped(board) do
    pieces =
      Map.new(board.pieces, fn {{color, type}, bb} ->
        {{Board.opposite(color), type}, transform_bb(bb, &mirror_v/1)}
      end)

    Board.build(pieces,
      side_to_move: Board.opposite(board.side_to_move),
      castling: vertical_castling(board.castling),
      en_passant: if(board.en_passant, do: mirror_v(board.en_passant))
    )
  end

  defp mirror(board, mode) do
    transform = if mode == :horizontal, do: &mirror_h/1, else: &mirror_v/1

    castling =
      if mode == :horizontal,
        do: horizontal_castling(board.castling),
        else: vertical_castling(board.castling)

    pieces = Map.new(board.pieces, fn {key, bb} -> {key, transform_bb(bb, transform)} end)

    Board.build(pieces,
      castling: castling,
      en_passant: if(board.en_passant, do: transform.(board.en_passant))
    )
  end

  defp mirror_h(square), do: Square.rank(square) * 8 + (7 - Square.file(square))

  defp mirror_v(square), do: (7 - Square.rank(square)) * 8 + Square.file(square)

  defp transform_bb(bitboard, transform) do
    bitboard
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc ||| 1 <<< transform.(square) end)
  end

  defp horizontal_castling(castling) do
    (castling &&& 0b0101) <<< 1 ||| (castling &&& 0b1010) >>> 1
  end

  defp vertical_castling(castling) do
    (castling &&& 0b0011) <<< 2 ||| (castling &&& 0b1100) >>> 2
  end
end
