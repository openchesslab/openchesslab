
alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule AttackedBreakdownHelpers do
  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def middlegame_position do
    Position.starting_position()
    |> move("e2", "e4")
    |> move("e7", "e5")
    |> move("g1", "f3")
    |> move("b8", "c6")
    |> move("f1", "b5")
    |> move("a7", "a6")
    |> move("b5", "a4")
    |> move("g8", "f6")
    |> move("e1", "g1")
    |> move("f8", "e7")
  end

  def check_position do
    Position.new(side_to_move: :white)
    |> Position.put_piece(square("e1"), {:white, :king})
    |> Position.put_piece(square("a1"), {:white, :rook})
    |> Position.put_piece(square("e2"), {:white, :pawn})
    |> Position.put_piece(square("e8"), {:black, :rook})
    |> Position.put_piece(square("a8"), {:black, :king})
  end

  def bitboard(position), do: Bitboard.from_position(position)

  def targets(position) do
    bitboard = bitboard(position)

    [
      {bitboard, :white, square("e4")},
      {bitboard, :black, square("e5")},
      {bitboard, :white, square("e2")},
      {bitboard, :black, square("e7")},
      {bitboard, :white, square("a1")},
      {bitboard, :black, square("a8")},
      {bitboard, :white, square("g1")},
      {bitboard, :black, square("g8")}
    ]
  end

  def attacked?(position) do
    targets(position)
    |> Enum.map(fn {board, color, square} ->
      Bitboard.attacked?(board, color, square)
    end)
  end

  def occupied(position) do
    board = bitboard(position)
    Bitboard.occupied(board)
  end

  def get(position) do
    board = bitboard(position)

    for square <- 0..63 do
      Bitboard.get(board, square)
    end
  end

  def rook_attacks(position) do
    board = bitboard(position)

    for square <- 0..63 do
      Bitboard.rook_attacks(board, square)
    end
  end

  def bishop_attacks(position) do
    board = bitboard(position)

    for square <- 0..63 do
      Bitboard.bishop_attacks(board, square)
    end
  end

  def queen_attacks(position) do
    board = bitboard(position)

    for square <- 0..63 do
      Bitboard.queen_attacks(board, square)
    end
  end

  def pawn_knight_king_attacks do
    for square <- 0..63 do
      Bitboard.pawn_attacks(:white, square)
      Bitboard.pawn_attacks(:black, square)
      Bitboard.knight_attacks(square)
      Bitboard.king_attacks(square)
    end
  end

  defp move(position, from, to) do
    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(square(from), square(to))
      )

    position
  end
end

starting = Position.starting_position()
middlegame = AttackedBreakdownHelpers.middlegame_position()
in_check = AttackedBreakdownHelpers.check_position()

IO.puts("Attack targets:")
IO.puts("starting:   #{length(AttackedBreakdownHelpers.targets(starting))}")
IO.puts("middlegame: #{length(AttackedBreakdownHelpers.targets(middlegame))}")
IO.puts("in check:   #{length(AttackedBreakdownHelpers.targets(in_check))}")
IO.puts("")

Benchee.run(
  %{
    "starting: occupied" => fn ->
      AttackedBreakdownHelpers.occupied(starting)
    end,
    "middlegame: occupied" => fn ->
      AttackedBreakdownHelpers.occupied(middlegame)
    end,
    "in check: occupied" => fn ->
      AttackedBreakdownHelpers.occupied(in_check)
    end,

    "starting: get all squares" => fn ->
      AttackedBreakdownHelpers.get(starting)
    end,
    "middlegame: get all squares" => fn ->
      AttackedBreakdownHelpers.get(middlegame)
    end,
    "in check: get all squares" => fn ->
      AttackedBreakdownHelpers.get(in_check)
    end,

    "starting: pawn/knight/king tables" => fn ->
      AttackedBreakdownHelpers.pawn_knight_king_attacks()
    end,
    "middlegame: pawn/knight/king tables" => fn ->
      AttackedBreakdownHelpers.pawn_knight_king_attacks()
    end,
    "in check: pawn/knight/king tables" => fn ->
      AttackedBreakdownHelpers.pawn_knight_king_attacks()
    end,

    "starting: rook attacks" => fn ->
      AttackedBreakdownHelpers.rook_attacks(starting)
    end,
    "middlegame: rook attacks" => fn ->
      AttackedBreakdownHelpers.rook_attacks(middlegame)
    end,
    "in check: rook attacks" => fn ->
      AttackedBreakdownHelpers.rook_attacks(in_check)
    end,

    "starting: bishop attacks" => fn ->
      AttackedBreakdownHelpers.bishop_attacks(starting)
    end,
    "middlegame: bishop attacks" => fn ->
      AttackedBreakdownHelpers.bishop_attacks(middlegame)
    end,
    "in check: bishop attacks" => fn ->
      AttackedBreakdownHelpers.bishop_attacks(in_check)
    end,

    "starting: queen attacks" => fn ->
      AttackedBreakdownHelpers.queen_attacks(starting)
    end,
    "middlegame: queen attacks" => fn ->
      AttackedBreakdownHelpers.queen_attacks(middlegame)
    end,
    "in check: queen attacks" => fn ->
      AttackedBreakdownHelpers.queen_attacks(in_check)
    end,

    "starting: attacked?" => fn ->
      AttackedBreakdownHelpers.attacked?(starting)
    end,
    "middlegame: attacked?" => fn ->
      AttackedBreakdownHelpers.attacked?(middlegame)
    end,
    "in check: attacked?" => fn ->
      AttackedBreakdownHelpers.attacked?(in_check)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
