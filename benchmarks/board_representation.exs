alias Chess.Board
alias Chess.Square
alias Chess.Position
alias Chess.PositionCodec

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

starting_encoded = PositionCodec.encode(starting_position)
realistic_encoded = PositionCodec.encode(realistic_position)

Benchee.run(
  %{
    "start: SHA-256" => fn ->
      :crypto.hash(:sha256, starting_encoded)
    end,
    "start: BLAKE2b" => fn ->
      :crypto.hash(:blake2b, starting_encoded)
    end,
    "start: BLAKE2s" => fn ->
      :crypto.hash(:blake2s, starting_encoded)
    end,
    "realistic: SHA-256" => fn ->
      :crypto.hash(:sha256, realistic_encoded)
    end,
    "realistic: BLAKE2b" => fn ->
      :crypto.hash(:blake2b, realistic_encoded)
    end,
    "realistic: BLAKE2s" => fn ->
      :crypto.hash(:blake2s, realistic_encoded)
    end
  },
  time: 5,
  memory_time: 2,
  print: [fast_warning: false]
)
