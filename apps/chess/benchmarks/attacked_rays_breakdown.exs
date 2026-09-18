alias Chess.Bitboard
alias Chess.Position
alias Chess.Square

import Bitwise

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

square = fn algebraic ->
  case Square.from_algebraic(algebraic) do
    square when is_integer(square) -> square
    {:error, reason} -> raise "invalid square #{algebraic}: #{inspect(reason)}"
  end
end

# Build small, controlled positions directly as bitboards.
#
# The target square is always e4.
#
# rook_open:
#   e4 <- h4
#
# rook_blocked:
#   e4 <- g4 blocker <- h4 rook
#
# bishop_open:
#   e4 <- h7
#
# bishop_blocked:
#   e4 <- g6 blocker <- h7 bishop

e4 = square.("e4")
h4 = square.("h4")
g4 = square.("g4")
h7 = square.("h7")
g6 = square.("g6")

rook_open =
  Bitboard.empty()
  |> Bitboard.put(e4, {:white, :king})
  |> Bitboard.put(h4, {:black, :rook})

rook_blocked =
  Bitboard.empty()
  |> Bitboard.put(e4, {:white, :king})
  |> Bitboard.put(g4, {:white, :pawn})
  |> Bitboard.put(h4, {:black, :rook})

bishop_open =
  Bitboard.empty()
  |> Bitboard.put(e4, {:white, :king})
  |> Bitboard.put(h7, {:black, :bishop})

bishop_blocked =
  Bitboard.empty()
  |> Bitboard.put(e4, {:white, :king})
  |> Bitboard.put(g6, {:white, :pawn})
  |> Bitboard.put(h7, {:black, :bishop})

starting = Bitboard.from_position(Position.starting_position())

# A more populated position, mainly to make the traversal behavior
# less artificial than the tiny ray fixtures above.
#
# This sequence is deliberately only used to create a representative
# middlegame board; legality is checked through Position.apply_move/2.
play! = fn position, moves ->
  Enum.reduce(moves, position, fn {from, to}, position ->
    from = square.(from)
    to = square.(to)

    case Chess.Move.new(from, to) |> then(&Position.apply_move(position, &1)) do
      {:ok, position} ->
        position

      {:error, reason} ->
        raise "could not apply #{from}-#{to}: #{inspect(reason)}"
    end
  end)
end

middlegame_position =
  Position.starting_position()
  |> play!.([
    {"e2", "e4"},
    {"e7", "e5"},
    {"g1", "f3"},
    {"b8", "c6"},
    {"f1", "b5"},
    {"a7", "a6"},
    {"b5", "a4"},
    {"g8", "f6"},
    {"e1", "g1"},
    {"f8", "e7"},
    {"d2", "d3"},
    {"b7", "b5"},
    {"a4", "b3"},
    {"d7", "d6"}
  ])

middlegame = Bitboard.from_position(middlegame_position)

# ------------------------------------------------------------
# Exact local reproduction of the current ray-attacked logic
# ------------------------------------------------------------

valid_ray_square? = fn from, to, step ->
  case step do
    step when step in [8, -8] ->
      to in 0..63

    1 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) + 1

    -1 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) - 1

    9 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) + 1

    7 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) - 1

    -7 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) + 1

    -9 ->
      to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end
end

# Returns whether the first occupied square on a ray is an
# enemy rook/queen or bishop/queen.
first_piece_on_ray = fn board, occupied, square, step, color, piece_types ->
  recurse = fn recurse, square ->
    next = square + step

    if valid_ray_square?.(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_types do
          [:rook, :queen] ->
            case color do
              :white -> (board.white_rooks &&& mask) != 0 or (board.white_queens &&& mask) != 0
              :black -> (board.black_rooks &&& mask) != 0 or (board.black_queens &&& mask) != 0
            end

          [:bishop, :queen] ->
            case color do
              :white ->
                (board.white_bishops &&& mask) != 0 or
                  (board.white_queens &&& mask) != 0

              :black ->
                (board.black_bishops &&& mask) != 0 or
                  (board.black_queens &&& mask) != 0
            end
        end
      else
        recurse.(recurse, next)
      end
    else
      false
    end
  end

  recurse.(recurse, square)
end

# Same traversal, but returns the number of squares inspected.
ray_length = fn occupied, square, step ->
  recurse = fn recurse, square, count ->
    next = square + step

    if valid_ray_square?.(square, next, step) do
      count = count + 1

      if (occupied &&& 1 <<< next) != 0 do
        count
      else
        recurse.(recurse, next, count)
      end
    else
      count
    end
  end

  recurse.(recurse, square, 0)
end

ray_count = fn board, square, steps ->
  occupied = Bitboard.occupied(board)

  Enum.reduce(steps, 0, fn step, total ->
    total + ray_length.(occupied, square, step)
  end)
end

rook_steps = [8, -8, 1, -1]
bishop_steps = [9, 7, -7, -9]

# ------------------------------------------------------------
# Benchmark
# ------------------------------------------------------------

Benchee.run(
  %{
    "starting: attacked?" => fn ->
      Bitboard.attacked?(starting, :black, e4)
    end,
    "middlegame: attacked?" => fn ->
      Bitboard.attacked?(middlegame, :black, e4)
    end,
    "rook open: attacked?" => fn ->
      Bitboard.attacked?(rook_open, :black, e4)
    end,
    "rook blocked: attacked?" => fn ->
      Bitboard.attacked?(rook_blocked, :black, e4)
    end,
    "bishop open: attacked?" => fn ->
      Bitboard.attacked?(bishop_open, :black, e4)
    end,
    "bishop blocked: attacked?" => fn ->
      Bitboard.attacked?(bishop_blocked, :black, e4)
    end,
    "rook open: rook_attacks" => fn ->
      Bitboard.rook_attacks(rook_open, e4)
    end,
    "rook blocked: rook_attacks" => fn ->
      Bitboard.rook_attacks(rook_blocked, e4)
    end,
    "bishop open: bishop_attacks" => fn ->
      Bitboard.bishop_attacks(bishop_open, e4)
    end,
    "bishop blocked: bishop_attacks" => fn ->
      Bitboard.bishop_attacks(bishop_blocked, e4)
    end,
    "rook open: 4 ray traversal" => fn ->
      occupied = Bitboard.occupied(rook_open)

      Enum.any?(rook_steps, fn step ->
        first_piece_on_ray.(
          rook_open,
          occupied,
          e4,
          step,
          :black,
          [:rook, :queen]
        )
      end)
    end,
    "rook blocked: 4 ray traversal" => fn ->
      occupied = Bitboard.occupied(rook_blocked)

      Enum.any?(rook_steps, fn step ->
        first_piece_on_ray.(
          rook_blocked,
          occupied,
          e4,
          step,
          :black,
          [:rook, :queen]
        )
      end)
    end,
    "bishop open: 4 ray traversal" => fn ->
      occupied = Bitboard.occupied(bishop_open)

      Enum.any?(bishop_steps, fn step ->
        first_piece_on_ray.(
          bishop_open,
          occupied,
          e4,
          step,
          :black,
          [:bishop, :queen]
        )
      end)
    end,
    "bishop blocked: 4 ray traversal" => fn ->
      occupied = Bitboard.occupied(bishop_blocked)

      Enum.any?(bishop_steps, fn step ->
        first_piece_on_ray.(
          bishop_blocked,
          occupied,
          e4,
          step,
          :black,
          [:bishop, :queen]
        )
      end)
    end,
    "rook open: ray squares inspected" => fn ->
      ray_count.(rook_open, e4, rook_steps)
    end,
    "rook blocked: ray squares inspected" => fn ->
      ray_count.(rook_blocked, e4, rook_steps)
    end,
    "bishop open: ray squares inspected" => fn ->
      ray_count.(bishop_open, e4, bishop_steps)
    end,
    "bishop blocked: ray squares inspected" => fn ->
      ray_count.(bishop_blocked, e4, bishop_steps)
    end,
    "starting: ray squares inspected" => fn ->
      ray_count.(starting, e4, rook_steps ++ bishop_steps)
    end,
    "middlegame: ray squares inspected" => fn ->
      ray_count.(middlegame, e4, rook_steps ++ bishop_steps)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1
)
