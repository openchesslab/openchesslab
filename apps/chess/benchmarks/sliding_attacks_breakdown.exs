alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule SlidingAttacksBenchmarkHelpers do
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

  def empty_board do
    Bitboard.empty()
  end

  def bitboard(position) do
    Bitboard.from_position(position)
  end

  def squares_for_piece(position, color, piece_type) do
    position
    |> Position.pieces()
    |> Enum.filter(fn
      {square, {^color, ^piece_type}} -> true
      _ -> false
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def apply_moves(position, moves) do
    Enum.reduce(moves, position, fn {from, to}, position ->
      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square(from), square(to))
        )

      position
    end)
  end
end

starting_position = Position.starting_position()
middlegame_position = SlidingAttacksBenchmarkHelpers.middlegame_position()
check_position = SlidingAttacksBenchmarkHelpers.check_position()

starting = SlidingAttacksBenchmarkHelpers.bitboard(starting_position)
middlegame = SlidingAttacksBenchmarkHelpers.bitboard(middlegame_position)
check = SlidingAttacksBenchmarkHelpers.bitboard(check_position)
empty = SlidingAttacksBenchmarkHelpers.empty_board()

starting_rooks =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    starting_position,
    :white,
    :rook
  )

starting_bishops =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    starting_position,
    :white,
    :bishop
  )

starting_queens =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    starting_position,
    :white,
    :queen
  )

middlegame_rooks =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    middlegame_position,
    :white,
    :rook
  )

middlegame_bishops =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    middlegame_position,
    :white,
    :bishop
  )

middlegame_queens =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    middlegame_position,
    :white,
    :queen
  )

check_rooks =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    check_position,
    :white,
    :rook
  )

check_bishops =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    check_position,
    :white,
    :bishop
  )

check_queens =
  SlidingAttacksBenchmarkHelpers.squares_for_piece(
    check_position,
    :white,
    :queen
  )

IO.puts("\nSliding piece counts:")

IO.puts(
  "starting:   rooks=#{length(starting_rooks)} " <>
    "bishops=#{length(starting_bishops)} " <>
    "queens=#{length(starting_queens)}"
)

IO.puts(
  "middlegame: rooks=#{length(middlegame_rooks)} " <>
    "bishops=#{length(middlegame_bishops)} " <>
    "queens=#{length(middlegame_queens)}"
)

IO.puts(
  "in check:   rooks=#{length(check_rooks)} " <>
    "bishops=#{length(check_bishops)} " <>
    "queens=#{length(check_queens)}"
)

Benchee.run(
  %{
    # Empty board gives us the maximum amount of ray traversal.
    "empty: rook attacks e4" => fn ->
      Bitboard.rook_attacks(empty, SlidingAttacksBenchmarkHelpers.square("e4"))
    end,
    "empty: bishop attacks e4" => fn ->
      Bitboard.bishop_attacks(empty, SlidingAttacksBenchmarkHelpers.square("e4"))
    end,
    "empty: queen attacks e4" => fn ->
      Bitboard.queen_attacks(empty, SlidingAttacksBenchmarkHelpers.square("e4"))
    end,

    # Starting position: heavily blocked sliding pieces.
    "starting: rook attacks" => fn ->
      Enum.map(starting_rooks, &Bitboard.rook_attacks(starting, &1))
    end,
    "starting: bishop attacks" => fn ->
      Enum.map(starting_bishops, &Bitboard.bishop_attacks(starting, &1))
    end,
    "starting: queen attacks" => fn ->
      Enum.map(starting_queens, &Bitboard.queen_attacks(starting, &1))
    end,

    # Middlegame: substantially more open rays.
    "middlegame: rook attacks" => fn ->
      Enum.map(middlegame_rooks, &Bitboard.rook_attacks(middlegame, &1))
    end,
    "middlegame: bishop attacks" => fn ->
      Enum.map(middlegame_bishops, &Bitboard.bishop_attacks(middlegame, &1))
    end,
    "middlegame: queen attacks" => fn ->
      Enum.map(middlegame_queens, &Bitboard.queen_attacks(middlegame, &1))
    end,

    # Check position.
    "in check: rook attacks" => fn ->
      Enum.map(check_rooks, &Bitboard.rook_attacks(check, &1))
    end,
    "in check: bishop attacks" => fn ->
      Enum.map(check_bishops, &Bitboard.bishop_attacks(check, &1))
    end,
    "in check: queen attacks" => fn ->
      Enum.map(check_queens, &Bitboard.queen_attacks(check, &1))
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
