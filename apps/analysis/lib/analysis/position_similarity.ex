defmodule Analysis.PositionSimilarity do
  @moduledoc """
  Compact per-position digest for corpus similarity search.

  The digest is not a feature vector: it packs the cheap, chess-stable facts
  that narrow a "similar positions" scan in PostgreSQL — side to move,
  castling rights, the exact material multiset, both king squares and the
  open/semi-open file geometry. Pawn structure itself stays in
  `positions.white_pawns`/`positions.black_pawns` (the existing search
  columns); the digest query joins them.

  Scoring and ranking happen in SQL; this module only computes and packs the
  digest. Every fact is a direct board read — no move generation, no
  catalogue extraction — so it stays cheap enough to compute at import time
  and in backfill jobs.

  Bit layout of the packed keys:

    * `material_key` — 10 nibbles, 4 bits per side/type in this order:
      white Q R B N P, then black Q R B N P. Counts are capped at 15, which
      is exact for any position reachable without extreme promotions.
    * `king_key` — 12 bits: white king file (3) + rank (3), then black king
      file (3) + rank (3). Files/ranks are zero-based from White's side.
    * `castling` — 4 bits: K=8, Q=4, k=2, q=1.
    * File masks — bit 0 is the a-file. `open_files` has neither pawn;
      `semi_open_white` has black pawns but no white pawns (White's file to
      use), `semi_open_black` the reverse.
  """

  alias Chess.Position

  defstruct side_to_move: :white,
            castling: 0,
            material_key: 0,
            king_key: 0,
            open_files: 0,
            semi_open_white: 0,
            semi_open_black: 0

  @type t :: %__MODULE__{
          side_to_move: :white | :black,
          castling: 0..15,
          material_key: non_neg_integer(),
          king_key: non_neg_integer(),
          open_files: 0..255,
          semi_open_white: 0..255,
          semi_open_black: 0..255
        }

  @material_slots [
    {:white, :queen},
    {:white, :rook},
    {:white, :bishop},
    {:white, :knight},
    {:white, :pawn},
    {:black, :queen},
    {:black, :rook},
    {:black, :bishop},
    {:black, :knight},
    {:black, :pawn}
  ]

  @castling_bits [
    white_kingside: 8,
    white_queenside: 4,
    black_kingside: 2,
    black_queenside: 1
  ]

  @spec digest(Position.t()) :: t()
  def digest(%Position{} = position) do
    {counts, kings, white_pawn_files, black_pawn_files} =
      Enum.reduce(
        Position.pieces(position),
        {%{}, %{}, 0, 0},
        fn {square, {color, type}}, {counts, kings, white_files, black_files} ->
          counts = Map.update(counts, {color, type}, 1, &(&1 + 1))
          kings = if type == :king, do: Map.put(kings, color, square), else: kings

          {white_files, black_files} =
            if type == :pawn do
              bit = Bitwise.bsl(1, rem(square, 8))

              if color == :white,
                do: {Bitwise.bor(white_files, bit), black_files},
                else: {white_files, Bitwise.bor(black_files, bit)}
            else
              {white_files, black_files}
            end

          {counts, kings, white_files, black_files}
        end
      )

    %__MODULE__{
      side_to_move: position.side_to_move,
      castling: castling_key(position.castling_rights),
      material_key: material_key(counts),
      king_key: king_key(kings),
      open_files:
        Bitwise.band(Bitwise.bnot(Bitwise.bor(white_pawn_files, black_pawn_files)), 0xFF),
      semi_open_white: Bitwise.band(black_pawn_files, Bitwise.bnot(white_pawn_files)),
      semi_open_black: Bitwise.band(white_pawn_files, Bitwise.bnot(black_pawn_files))
    }
  end

  defp material_key(counts) do
    @material_slots
    |> Enum.with_index()
    |> Enum.reduce(0, fn {{color, type}, slot}, key ->
      count = min(Map.get(counts, {color, type}, 0), 15)
      Bitwise.bor(key, Bitwise.bsl(count, slot * 4))
    end)
  end

  # Corpus positions always have both kings; the defaults keep the function
  # total for editor drafts.
  defp king_key(kings) do
    white = Map.get(kings, :white, 4)
    black = Map.get(kings, :black, 60)

    Bitwise.bor(
      rem(white, 8),
      Bitwise.bor(
        Bitwise.bsl(div(white, 8), 3),
        Bitwise.bor(
          Bitwise.bsl(rem(black, 8), 6),
          Bitwise.bsl(div(black, 8), 9)
        )
      )
    )
  end

  defp castling_key(rights) do
    Enum.reduce(@castling_bits, 0, fn {right, bit}, key ->
      if MapSet.member?(rights, right), do: Bitwise.bor(key, bit), else: key
    end)
  end
end
