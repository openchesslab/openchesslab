alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  import Bitwise

  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def middlegame_position do
    Position.starting_position()
    |> apply_moves([
      {"e2", "e4"},
      {"e7", "e5"},
      {"g1", "f3"},
      {"b8", "c6"},
      {"f1", "b5"},
      {"a7", "a6"},
      {"b5", "a4"},
      {"g8", "f6"},
      {"e1", "g1"},
      {"f8", "e7"}
    ])
  end

  def check_position do
    Position.new(side_to_move: :white)
    |> Position.put_piece(square("e1"), {:white, :king})
    |> Position.put_piece(square("a1"), {:white, :rook})
    |> Position.put_piece(square("e2"), {:white, :pawn})
    |> Position.put_piece(square("e8"), {:black, :rook})
    |> Position.put_piece(square("a8"), {:black, :king})
  end

  def regular_candidates(position) do
    bitboard = Bitboard.from_position(position)
    side = position.side_to_move
    king_square = king_square(position, side)

    bitboard
    |> Bitboard.pseudo_moves(side)
    |> Enum.flat_map(fn {from, destinations} ->
      piece = Position.piece_at(position, from)

      for to <- 0..63,
          band(destinations, bsl(1, to)) != 0 do
        promotions =
          if promotion_move?(piece, from) do
            [:queen, :rook, :bishop, :knight]
          else
            [nil]
          end

        for promotion <- promotions do
          %{
            bitboard: bitboard,
            side: side,
            king_square: king_square,
            move: Move.new(from, to, promotion),
            piece: piece
          }
        end
      end
    end)
    |> List.flatten()
  end

  def after_move_candidates(candidates) do
    Enum.map(candidates, fn %{
                              bitboard: bitboard,
                              move: move,
                              piece: piece
                            } ->
      Bitboard.after_move(bitboard, move, piece)
    end)
  end

  def attacked_candidates(candidates) do
    Enum.map(candidates, fn %{
                              bitboard: bitboard,
                              side: side,
                              king_square: king_square,
                              move: move,
                              piece: piece
                            } ->
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
    end)
  end

  def validate_candidates(candidates) do
    Enum.filter(candidates, fn %{
                                 bitboard: bitboard,
                                 side: side,
                                 king_square: king_square,
                                 move: move,
                                 piece: piece
                               } ->
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
    end)
  end

  defp apply_moves(position, moves) do
    Enum.reduce(moves, position, fn {from, to}, position ->
      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square(from), square(to))
        )

      position
    end)
  end

  defp king_square(position, color) do
    position
    |> Position.pieces()
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

starting_position = Position.starting_position()
middlegame_position = BenchmarkHelpers.middlegame_position()
check_position = BenchmarkHelpers.check_position()

starting_candidates = BenchmarkHelpers.regular_candidates(starting_position)
middlegame_candidates = BenchmarkHelpers.regular_candidates(middlegame_position)
check_candidates = BenchmarkHelpers.regular_candidates(check_position)

IO.puts("\nCandidate counts:")
IO.puts("starting:   #{length(starting_candidates)}")
IO.puts("middlegame: #{length(middlegame_candidates)}")
IO.puts("in check:   #{length(check_candidates)}")

Benchee.run(
  %{
    "starting: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(
        Bitboard.from_position(starting_position),
        starting_position.side_to_move
      )
    end,
    "middlegame: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(
        Bitboard.from_position(middlegame_position),
        middlegame_position.side_to_move
      )
    end,
    "in check: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(
        Bitboard.from_position(check_position),
        check_position.side_to_move
      )
    end,
    "starting: candidate generation" => fn ->
      BenchmarkHelpers.regular_candidates(starting_position)
    end,
    "middlegame: candidate generation" => fn ->
      BenchmarkHelpers.regular_candidates(middlegame_position)
    end,
    "in check: candidate generation" => fn ->
      BenchmarkHelpers.regular_candidates(check_position)
    end,
    "starting: after_move" => fn ->
      BenchmarkHelpers.after_move_candidates(starting_candidates)
    end,
    "middlegame: after_move" => fn ->
      BenchmarkHelpers.after_move_candidates(middlegame_candidates)
    end,
    "in check: after_move" => fn ->
      BenchmarkHelpers.after_move_candidates(check_candidates)
    end,
    "starting: attacked?" => fn ->
      BenchmarkHelpers.attacked_candidates(starting_candidates)
    end,
    "middlegame: attacked?" => fn ->
      BenchmarkHelpers.attacked_candidates(middlegame_candidates)
    end,
    "in check: attacked?" => fn ->
      BenchmarkHelpers.attacked_candidates(check_candidates)
    end,
    "starting: validate candidates" => fn ->
      BenchmarkHelpers.validate_candidates(starting_candidates)
    end,
    "middlegame: validate candidates" => fn ->
      BenchmarkHelpers.validate_candidates(middlegame_candidates)
    end,
    "in check: validate candidates" => fn ->
      BenchmarkHelpers.validate_candidates(check_candidates)
    end,
    "starting: legal_moves" => fn ->
      moves = Position.legal_moves(starting_position)

      unless length(moves) == 20 do
        raise("expected 20 moves")
      end

      moves
    end,
    "middlegame: legal_moves" => fn ->
      Position.legal_moves(middlegame_position)
    end,
    "in check: legal_moves" => fn ->
      Position.legal_moves(check_position)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
