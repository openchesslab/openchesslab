defmodule Features.Chess.AttackTables do
  @moduledoc """
  Precomputed attack tables for all piece types.

  Tables are built once at compile time:

    * offset attacks: knight, king, pawn targets and pawn attackers
    * slider rays: ordered square lists per direction for rooks and bishops,
      walked at runtime against an occupancy bitboard.
  """

  import Bitwise

  @knight_deltas [
    {1, 2},
    {2, 1},
    {2, -1},
    {1, -2},
    {-1, -2},
    {-2, -1},
    {-2, 1},
    {-1, 2}
  ]

  @king_deltas [
    {1, 0},
    {1, 1},
    {0, 1},
    {-1, 1},
    {-1, 0},
    {-1, -1},
    {0, -1},
    {1, -1}
  ]

  @diagonal_dirs [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]
  @straight_dirs [{0, 1}, {0, -1}, {1, 0}, {-1, 0}]

  {knight_attacks, king_attacks} =
    (fn ->
       build = fn deltas ->
         for square <- 0..63 do
           file = rem(square, 8)
           rank = div(square, 8)

           targets =
             for {df, dr} <- deltas,
                 f = file + df,
                 r = rank + dr,
                 f >= 0 and f <= 7 and r >= 0 and r <= 7,
                 do: r * 8 + f

           Enum.reduce(targets, 0, fn target, acc -> acc ||| 1 <<< target end)
         end
         |> List.to_tuple()
       end

       {build.(@knight_deltas), build.(@king_deltas)}
     end).()

  @knight_attacks knight_attacks
  @king_attacks king_attacks

  {rook_rays, bishop_rays} =
    (fn ->
       build = fn dirs ->
         for square <- 0..63 do
           file = rem(square, 8)
           rank = div(square, 8)

           for {df, dr} <- dirs do
             for step <- 1..7,
                 f = file + step * df,
                 r = rank + step * dr,
                 f >= 0 and f <= 7 and r >= 0 and r <= 7 do
               r * 8 + f
             end
           end
         end
         |> List.to_tuple()
       end

       {build.(@straight_dirs), build.(@diagonal_dirs)}
     end).()

  @rook_rays rook_rays
  @bishop_rays bishop_rays

  # Pawn tables. `sign` is +1 for white (moves up) and -1 for black.
  #
  # Targets: from a source square, a white pawn attacks +7 (toward the
  # a-file, needs file >= 1) and +9 (toward the h-file, needs file <= 6);
  # black mirrors with -7 and -9.
  #
  # Sources: which pawn squares attack a given target square, i.e. the
  # inverse offsets with the validity conditions applied to the target.
  {white_pawn_targets, black_pawn_targets, white_pawn_sources, black_pawn_sources} =
    (fn ->
       build_targets = fn sign ->
         for square <- 0..63 do
           file = rem(square, 8)

           ok_7 = (sign > 0 and file >= 1) or (sign < 0 and file <= 6)
           ok_9 = (sign > 0 and file <= 6) or (sign < 0 and file >= 1)

           targets =
             for {delta, ok} <- [{7 * sign, ok_7}, {9 * sign, ok_9}],
                 ok,
                 target = square + delta,
                 target >= 0 and target <= 63,
                 do: target

           Enum.reduce(targets, 0, fn target, acc -> acc ||| 1 <<< target end)
         end
         |> List.to_tuple()
       end

       build_sources = fn sign ->
         for target <- 0..63 do
           file = rem(target, 8)

           ok_7 = (sign > 0 and file <= 6) or (sign < 0 and file >= 1)
           ok_9 = (sign > 0 and file >= 1) or (sign < 0 and file <= 6)

           sources =
             for {delta, ok} <- [{-7 * sign, ok_7}, {-9 * sign, ok_9}],
                 ok,
                 source = target + delta,
                 source >= 0 and source <= 63,
                 do: source

           Enum.reduce(sources, 0, fn source, acc -> acc ||| 1 <<< source end)
         end
         |> List.to_tuple()
       end

       {build_targets.(1), build_targets.(-1), build_sources.(1), build_sources.(-1)}
     end).()

  @white_pawn_targets white_pawn_targets
  @black_pawn_targets black_pawn_targets
  @white_pawn_sources white_pawn_sources
  @black_pawn_sources black_pawn_sources

  @doc "Bitboard of squares attacked by a knight on `square`."
  def knight(square), do: elem(@knight_attacks, square)

  @doc "Bitboard of squares attacked by a king on `square`."
  def king(square), do: elem(@king_attacks, square)

  @doc "Bitboard of squares attacked by a white pawn on `square`."
  def white_pawn(square), do: elem(@white_pawn_targets, square)

  @doc "Bitboard of squares attacked by a black pawn on `square`."
  def black_pawn(square), do: elem(@black_pawn_targets, square)

  @doc "Bitboard of squares from which a pawn of `color` attacks `square`."
  def pawn_attackers(:white, square), do: elem(@white_pawn_sources, square)
  def pawn_attackers(:black, square), do: elem(@black_pawn_sources, square)

  @doc "Ordered ray square lists per direction for a rook on `square`."
  def rook_rays(square), do: elem(@rook_rays, square)

  @doc "Ordered ray square lists per direction for a bishop on `square`."
  def bishop_rays(square), do: elem(@bishop_rays, square)

  @doc "Bitboard of squares attacked by a rook on `square` given `occupancy`."
  def rook_attacks(square, occupancy) do
    reduce_rays(elem(@rook_rays, square), occupancy)
  end

  @doc "Bitboard of squares attacked by a bishop on `square` given `occupancy`."
  def bishop_attacks(square, occupancy) do
    reduce_rays(elem(@bishop_rays, square), occupancy)
  end

  @doc "Bitboard of squares attacked by a queen on `square` given `occupancy`."
  def queen_attacks(square, occupancy) do
    rook_attacks(square, occupancy) ||| bishop_attacks(square, occupancy)
  end

  @doc """
  Bitboard of squares reachable along `ray` from its origin, including the
  first occupied square (the blocker itself).
  """
  def ray_bits([], _occupancy), do: 0

  def ray_bits([square | rest], occupancy) do
    bit = 1 <<< square

    if (occupancy &&& bit) == 0 do
      bit ||| ray_bits(rest, occupancy)
    else
      bit
    end
  end

  @doc "First occupied square along `ray`, or `nil` when the ray is clear."
  def first_blocker([], _occupancy), do: nil

  def first_blocker([square | rest], occupancy) do
    if (occupancy &&& 1 <<< square) == 0 do
      first_blocker(rest, occupancy)
    else
      square
    end
  end

  defp reduce_rays(rays, occupancy) do
    Enum.reduce(rays, 0, fn ray, acc -> acc ||| ray_bits(ray, occupancy) end)
  end
end
