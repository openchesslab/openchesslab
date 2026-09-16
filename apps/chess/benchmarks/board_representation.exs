alias Chess.Position
alias Chess.PositionCanonicalizer
alias Chess.PositionCodec
alias Chess.PositionHash
alias Chess.PositionProperties

import Bitwise

defmodule BenchmarkHelpers do
  import Bitwise

  def popcount(value) do
    popcount(value, 0)
  end

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(value &&& value - 1, count + 1)
  end
end

starting_position = Position.starting_position()

realistic_position =
  Position.new(
    board:
      Chess.Board.empty()
      |> Chess.Board.put(Chess.Square.from_algebraic("g1"), {:white, :king})
      |> Chess.Board.put(Chess.Square.from_algebraic("c1"), {:white, :queen})
      |> Chess.Board.put(Chess.Square.from_algebraic("a1"), {:white, :rook})
      |> Chess.Board.put(Chess.Square.from_algebraic("f1"), {:white, :bishop})
      |> Chess.Board.put(Chess.Square.from_algebraic("c3"), {:white, :knight})
      |> Chess.Board.put(Chess.Square.from_algebraic("a2"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("b3"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("d4"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("f3"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("g2"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("h2"), {:white, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("g8"), {:black, :king})
      |> Chess.Board.put(Chess.Square.from_algebraic("c8"), {:black, :queen})
      |> Chess.Board.put(Chess.Square.from_algebraic("a8"), {:black, :rook})
      |> Chess.Board.put(Chess.Square.from_algebraic("f8"), {:black, :bishop})
      |> Chess.Board.put(Chess.Square.from_algebraic("c6"), {:black, :knight})
      |> Chess.Board.put(Chess.Square.from_algebraic("a7"), {:black, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("b6"), {:black, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("d5"), {:black, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("f6"), {:black, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("g7"), {:black, :pawn})
      |> Chess.Board.put(Chess.Square.from_algebraic("h7"), {:black, :pawn}),
    side_to_move: :white,
    castling_rights: MapSet.new([:white_kingside, :black_kingside]),
    en_passant: nil
  )

starting_bitboard = Chess.Bitboard.from_position(starting_position)
realistic_bitboard = Chess.Bitboard.from_position(realistic_position)

Benchee.run(
  %{
    "start: occupied from position" => fn ->
      PositionProperties.occupied(starting_position)
    end,
    "start: occupied from bitboard" => fn ->
      PositionProperties.occupied(starting_bitboard)
    end,
    "realistic: occupied from position" => fn ->
      PositionProperties.occupied(realistic_position)
    end,
    "realistic: occupied from bitboard" => fn ->
      PositionProperties.occupied(realistic_bitboard)
    end,
    "start: position encode" => fn ->
      PositionCodec.encode(starting_position)
    end,
    "start: canonical encode" => fn ->
      PositionCanonicalizer.encode(starting_position)
    end,
    "start: position hash" => fn ->
      PositionHash.hash(starting_position)
    end,
    "realistic: position encode" => fn ->
      PositionCodec.encode(realistic_position)
    end,
    "realistic: canonical encode" => fn ->
      PositionCanonicalizer.encode(realistic_position)
    end,
    "realistic: position hash" => fn ->
      PositionHash.hash(realistic_position)
    end,
    "start: material" => fn ->
      PositionProperties.material(starting_position)
    end,
    "realistic: material" => fn ->
      PositionProperties.material(realistic_position)
    end,
    "start: material from position" => fn ->
      PositionProperties.material(starting_position)
    end,
    "start: material from bitboard" => fn ->
      PositionProperties.material(starting_bitboard)
    end,
    "realistic: material from position" => fn ->
      PositionProperties.material(realistic_position)
    end,
    "realistic: material from bitboard" => fn ->
      PositionProperties.material(realistic_bitboard)
    end
  },
  time: 5,
  memory_time: 2,
  print: [fast_warning: false]
)
