alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule LegalMoveValidationBenchmark do
  def starting_position do
    Position.starting_position()
  end

  def middlegame_position do
    Position.new(
      board:
        Chess.Board.empty()
        # e1
        |> Chess.Board.put(4, {:white, :king})
        # g1
        |> Chess.Board.put(6, {:white, :knight})
        # d2
        |> Chess.Board.put(11, {:white, :pawn})
        # e2
        |> Chess.Board.put(12, {:white, :pawn})
        # f3
        |> Chess.Board.put(21, {:white, :bishop})
        # e4
        |> Chess.Board.put(28, {:white, :pawn})
        # d5
        |> Chess.Board.put(35, {:white, :pawn})
        # e5
        |> Chess.Board.put(36, {:black, :pawn})
        # d6
        |> Chess.Board.put(43, {:black, :pawn})
        # d7
        |> Chess.Board.put(51, {:black, :pawn})
        # e8
        |> Chess.Board.put(60, {:black, :king})
        # g8
        |> Chess.Board.put(62, {:black, :knight}),
      side_to_move: :white
    )
  end

  def in_check_position do
    Position.new(
      board:
        Chess.Board.empty()
        # e1
        |> Chess.Board.put(4, {:white, :king})
        # e2
        |> Chess.Board.put(12, {:white, :pawn})
        # e8
        |> Chess.Board.put(60, {:black, :king})
        # e7
        |> Chess.Board.put(52, {:black, :rook}),
      side_to_move: :white
    )
  end

  def candidates(position) do
    bitboard = Bitboard.from_position(position)
    side = position.side_to_move

    Bitboard.pseudo_moves(bitboard, side)
    |> Enum.flat_map(fn {from, destinations} ->
      piece = Position.piece_at(position, from)

      for to <- 0..63,
          Bitwise.band(destinations, Bitwise.bsl(1, to)) != 0 do
        promotion =
          if promotion_move?(piece, from) do
            [:queen, :rook, :bishop, :knight]
          else
            [nil]
          end

        for promotion_piece <- promotion do
          {Move.new(from, to, promotion_piece), piece}
        end
      end
    end)
    |> List.flatten()
  end

  def validation_samples(position) do
    bitboard = Bitboard.from_position(position)
    side = position.side_to_move
    king_square = king_square(position, side)

    candidates(position)
    |> Enum.map(fn {move, piece} ->
      {move, piece, bitboard, side, king_square}
    end)
  end

  def after_move_only({move, piece, bitboard, _side, _king_square}) do
    Bitboard.after_move(bitboard, move, piece)
  end

  def attacked_only({move, piece, bitboard, side, king_square}) do
    next_bitboard = Bitboard.after_move(bitboard, move, piece)

    king_square =
      case piece do
        {^side, :king} -> move.to
        _ -> king_square
      end

    Bitboard.attacked?(
      next_bitboard,
      opposite_color(side),
      king_square
    )
  end

  def full_validation({move, piece, bitboard, side, king_square}) do
    next_bitboard = Bitboard.after_move(bitboard, move, piece)

    king_square =
      case piece do
        {^side, :king} -> move.to
        _ -> king_square
      end

    not Bitboard.attacked?(
      next_bitboard,
      opposite_color(side),
      king_square
    )
  end

  def current_legal_moves(position) do
    Position.legal_moves(position)
  end

  defp king_square(position, color) do
    position.board
    |> Chess.Board.pieces()
    |> Enum.find_value(fn
      {square, {^color, :king}} -> square
      _ -> nil
    end)
  end

  defp promotion_move?({:white, :pawn}, square), do: square in 48..55
  defp promotion_move?({:black, :pawn}, square), do: square in 8..15
  defp promotion_move?(_piece, _square), do: false

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white
end

positions = %{
  starting: LegalMoveValidationBenchmark.starting_position(),
  middlegame: LegalMoveValidationBenchmark.middlegame_position(),
  in_check: LegalMoveValidationBenchmark.in_check_position()
}

samples =
  Map.new(positions, fn {name, position} ->
    {name, LegalMoveValidationBenchmark.validation_samples(position)}
  end)

IO.puts("Candidate counts:\n")

Enum.each(samples, fn {name, candidates} ->
  IO.puts("#{name}: #{length(candidates)}")
end)

IO.puts("\n")

benchmarks =
  Enum.flat_map(samples, fn {name, candidates} ->
    [
      {"#{name}: after_move only",
       fn ->
         Enum.each(candidates, &LegalMoveValidationBenchmark.after_move_only/1)
       end},
      {"#{name}: attacked? validation",
       fn ->
         Enum.each(candidates, &LegalMoveValidationBenchmark.attacked_only/1)
       end},
      {"#{name}: after_move + attacked?",
       fn ->
         Enum.each(candidates, &LegalMoveValidationBenchmark.full_validation/1)
       end},
      {"#{name}: legal_moves",
       fn ->
         LegalMoveValidationBenchmark.current_legal_moves(Map.fetch!(positions, name))
       end}
    ]
  end)

Benchee.run(
  benchmarks,
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  formatters: [
    Benchee.Formatters.Console
  ]
)
