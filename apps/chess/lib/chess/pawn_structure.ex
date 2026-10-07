defmodule Chess.PawnStructure do
  @moduledoc """
  Exact pawn occupancy for both colors.

  Pawn structure intentionally excludes every other aspect of position
  identity, including side to move, castling rights, en passant state and
  non-pawn pieces.

  Color reversal swaps White and Black while reflecting ranks so pawn
  direction remains meaningful. For example, a White pawn on d4 becomes
  a Black pawn on d5.

  File reflection mirrors the structure across the vertical center line
  while preserving colors and ranks. For example, a White pawn on b4
  becomes a White pawn on g4.

  Pawn shifts are structural transformations rather than chess moves.
  They relocate one pawn between two squares without validating move
  geometry or non-pawn occupancy.
  """

  import Bitwise

  alias Chess.Bitboard
  alias Chess.Position

  @enforce_keys [
    :white,
    :black
  ]

  defstruct [
    :white,
    :black
  ]

  @type t :: %__MODULE__{
          white: non_neg_integer(),
          black: non_neg_integer()
        }

  @type color :: :white | :black

  @type shift_error ::
          :invalid_color
          | :invalid_square
          | :same_square
          | :missing_pawn
          | :target_has_pawn

  @spec from_position(Position.t()) :: t()
  def from_position(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> from_bitboard()
  end

  @spec from_bitboard(Bitboard.t()) :: t()
  def from_bitboard(%Bitboard{} = board) do
    %__MODULE__{
      white: board.white_pawns,
      black: board.black_pawns
    }
  end

  @doc """
  Relocates one pawn inside a pawn structure.

  This is a structural transformation, not chess move validation.
  The source square must contain a pawn of the requested color and
  the destination square must not contain either color's pawn.

  Non-pawn occupancy is intentionally unknown to a pawn structure.

  This makes transformations such as `h2 -> h3` useful for constructing
  exact searches for nearby pawn structures.
  """
  @spec shift_pawn(
          t(),
          color(),
          Chess.Square.t(),
          Chess.Square.t()
        ) ::
          {:ok, t()}
          | {:error, shift_error()}
  def shift_pawn(%__MODULE__{} = structure, color, from, to) do
    cond do
      color not in [
        :white,
        :black
      ] ->
        {:error, :invalid_color}

      not valid_square?(from) or
          not valid_square?(to) ->
        {:error, :invalid_square}

      from == to ->
        {:error, :same_square}

      not pawn_on?(
        structure,
        color,
        from
      ) ->
        {:error, :missing_pawn}

      pawn_on_any_color?(
        structure,
        to
      ) ->
        {:error, :target_has_pawn}

      true ->
        {:ok,
         relocate_pawn(
           structure,
           color,
           from,
           to
         )}
    end
  end

  @doc """
  Returns every distinct pawn structure produced by shifting exactly one
  pawn one rank forward in its color's normal direction.

  White pawns are shifted toward higher square numbers and Black pawns
  toward lower square numbers. A variant is omitted when the destination
  lies outside the board or already contains a pawn.

  These are structural transformations, not legal chess moves. Occupancy
  by non-pawn pieces is intentionally unknown.

  This function is directional. Use `single_rank_neighbors/1` when the
  relationship between two structures should be direction-independent.
  """
  @spec single_pushes(t()) :: [t()]
  def single_pushes(%__MODULE__{} = structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        shift_variants(
          structure,
          color,
          from,
          [
            forward_step(color)
          ]
        )
      end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Returns every distinct pawn structure that is one single-rank pawn
  displacement away from the given structure.

  The relationship is direction-independent. If structure A can become
  structure B through one forward structural pawn shift, then A is a
  neighbor of B and B is a neighbor of A.

  For each pawn this therefore considers both the pawn's normal forward
  direction and the opposite direction. Variants whose destination lies
  outside the board or already contains a pawn are omitted.

  These are structural transformations, not legal chess moves.
  """
  @spec single_rank_neighbors(t()) :: [t()]
  def single_rank_neighbors(%__MODULE__{} = structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        forward =
          forward_step(color)

        shift_variants(
          structure,
          color,
          from,
          [
            forward,
            -forward
          ]
        )
      end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Returns every distinct pawn structure produced by removing exactly one pawn.

  The transformation is directional: every returned structure contains exactly
  one fewer pawn than the source structure. White pawns are considered before
  Black pawns and squares are processed in ascending square order.

  This is a structural transformation and does not model how the pawn
  disappeared from the board.
  """
  @spec single_pawn_removals(t()) :: [t()]
  def single_pawn_removals(%__MODULE__{} = structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.map(fn square ->
        remove_pawn(
          structure,
          color,
          square
        )
      end)
    end)
  end

  @doc """
  Returns the same pawn structure from the opposite color perspective.

  Colors are swapped and ranks are reflected:

    * rank 1 <-> rank 8
    * rank 2 <-> rank 7
    * rank 3 <-> rank 6
    * rank 4 <-> rank 5

  Files are preserved.
  """
  @spec color_reversed(t()) :: t()
  def color_reversed(%__MODULE__{white: white, black: black}) do
    %__MODULE__{
      white: flip_ranks(black),
      black: flip_ranks(white)
    }
  end

  @doc """
  Reflects the pawn structure across the vertical center line.

  Colors and ranks are preserved while files are mirrored:

    * a <-> h
    * b <-> g
    * c <-> f
    * d <-> e
  """
  @spec file_reflected(t()) :: t()
  def file_reflected(%__MODULE__{white: white, black: black}) do
    %__MODULE__{
      white: flip_files(white),
      black: flip_files(black)
    }
  end

  @doc """
  Returns every distinct pawn structure equivalent under the supported
  symmetries.

  The equivalence class contains up to four structures:

    * the exact structure
    * color reversal
    * file reflection
    * color reversal combined with file reflection

  Structures that coincide because of symmetry are returned only once.
  """
  @spec symmetries(t()) :: [t()]
  def symmetries(%__MODULE__{} = structure) do
    color_reversed =
      color_reversed(structure)

    file_reflected =
      file_reflected(structure)

    color_reversed_and_file_reflected =
      color_reversed
      |> file_reflected()

    [
      structure,
      color_reversed,
      file_reflected,
      color_reversed_and_file_reflected
    ]
    |> Enum.uniq()
  end

  defp shift_variants(structure, color, from, steps) do
    Enum.flat_map(
      steps,
      fn step ->
        case shift_pawn(
               structure,
               color,
               from,
               from + step
             ) do
          {:ok, shifted} ->
            [
              shifted
            ]

          {:error, _reason} ->
            []
        end
      end
    )
  end

  defp remove_pawn(structure, color, square) do
    pawns =
      structure
      |> color_pawns(color)
      |> band(
        bnot(
          bsl(
            1,
            square
          )
        )
      )

    put_color_pawns(
      structure,
      color,
      pawns
    )
  end

  defp relocate_pawn(structure, color, from, to) do
    pawns =
      structure
      |> color_pawns(color)
      |> band(
        bnot(
          bsl(
            1,
            from
          )
        )
      )
      |> bor(
        bsl(
          1,
          to
        )
      )

    put_color_pawns(
      structure,
      color,
      pawns
    )
  end

  defp pawn_squares(pawns) do
    for square <- 0..63,
        band(
          pawns,
          bsl(
            1,
            square
          )
        ) != 0 do
      square
    end
  end

  defp forward_step(:white) do
    8
  end

  defp forward_step(:black) do
    -8
  end

  defp pawn_on?(structure, color, square) do
    structure
    |> color_pawns(color)
    |> band(
      bsl(
        1,
        square
      )
    )
    |> Kernel.!=(0)
  end

  defp pawn_on_any_color?(%__MODULE__{white: white, black: black}, square) do
    white
    |> bor(black)
    |> band(
      bsl(
        1,
        square
      )
    )
    |> Kernel.!=(0)
  end

  defp color_pawns(%__MODULE__{white: white}, :white) do
    white
  end

  defp color_pawns(%__MODULE__{black: black}, :black) do
    black
  end

  defp put_color_pawns(structure, :white, pawns) do
    %{
      structure
      | white: pawns
    }
  end

  defp put_color_pawns(structure, :black, pawns) do
    %{
      structure
      | black: pawns
    }
  end

  defp valid_square?(square) do
    is_integer(square) and
      square in 0..63
  end

  defp flip_ranks(bitboard) do
    0..7
    |> Enum.reduce(
      0,
      fn rank, reversed ->
        rank_bits =
          bitboard
          |> bsr(rank * 8)
          |> band(0xFF)

        bor(
          reversed,
          bsl(
            rank_bits,
            (7 - rank) * 8
          )
        )
      end
    )
  end

  defp flip_files(bitboard) do
    0..7
    |> Enum.reduce(
      0,
      fn rank, reflected ->
        rank_bits =
          bitboard
          |> bsr(rank * 8)
          |> band(0xFF)

        bor(
          reflected,
          bsl(
            reverse_byte(rank_bits),
            rank * 8
          )
        )
      end
    )
  end

  defp reverse_byte(byte) do
    0..7
    |> Enum.reduce(
      0,
      fn file, reversed ->
        if band(
             byte,
             bsl(
               1,
               file
             )
           ) == 0 do
          reversed
        else
          bor(
            reversed,
            bsl(
              1,
              7 - file
            )
          )
        end
      end
    )
  end
end
