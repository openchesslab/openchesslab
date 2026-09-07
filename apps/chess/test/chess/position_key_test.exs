defmodule Chess.PositionKeyTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.PositionHash
  alias Chess.PositionKey
  alias Chess.PositionTransform

  describe "exact/1" do
    test "returns the position encoding" do
      position = Position.starting_position()

      assert PositionKey.exact(position) ==
               PositionCodec.encode(position)
    end

    test "same positions have the same key" do
      position = Position.starting_position()

      assert PositionKey.exact(position) ==
               PositionKey.exact(position)
    end

    test "different positions have different keys" do
      position = Position.starting_position()

      changed_position =
        position
        |> Position.put_piece(
          Chess.Square.from_algebraic("e4"),
          {:white, :pawn}
        )

      refute PositionKey.exact(position) ==
               PositionKey.exact(changed_position)
    end

    test "side to move is part of the exact key" do
      position = Position.starting_position()

      changed_position = %{position | side_to_move: :black}

      refute PositionKey.exact(position) ==
               PositionKey.exact(changed_position)
    end

    test "castling rights are part of the exact key" do
      position = Position.starting_position()

      changed_position = %{position | castling_rights: MapSet.new()}

      refute PositionKey.exact(position) ==
               PositionKey.exact(changed_position)
    end

    test "en passant is part of the exact key" do
      position = Position.starting_position()

      changed_position = %{position | en_passant: 28}

      refute PositionKey.exact(position) ==
               PositionKey.exact(changed_position)
    end
  end

  describe "exact_hash/1" do
    test "returns the hash of the exact key" do
      position = Position.starting_position()

      assert PositionKey.exact_hash(position) ==
               PositionHash.hash(PositionKey.exact(position))
    end

    test "same positions have the same hash" do
      position = Position.starting_position()

      assert PositionKey.exact_hash(position) ==
               PositionKey.exact_hash(position)
    end
  end

  describe "equivalent/2" do
    test "color-swapped positions have the same equivalent key" do
      position = Position.starting_position()
      swapped = PositionTransform.swap_colors(position)

      assert PositionKey.equivalent(position, :color_swap) ==
               PositionKey.equivalent(swapped, :color_swap)
    end

    test "returns one of the two possible encodings" do
      position = Position.starting_position()

      normal = PositionCodec.encode(position)

      swapped =
        position
        |> PositionTransform.swap_colors()
        |> PositionCodec.encode()

      key = PositionKey.equivalent(position, :color_swap)

      assert key == min(normal, swapped)
    end

    test "swapping twice preserves the equivalent key" do
      position = Position.starting_position()

      swapped =
        position
        |> PositionTransform.swap_colors()
        |> PositionTransform.swap_colors()

      assert PositionKey.equivalent(position, :color_swap) ==
               PositionKey.equivalent(swapped, :color_swap)
    end

    test "exact keys of color-swapped positions can differ" do
      position = Position.starting_position()
      swapped = PositionTransform.swap_colors(position)

      refute PositionKey.exact(position) ==
               PositionKey.exact(swapped)
    end

    test "equivalent key can equal exact key when original is canonical" do
      position = Position.starting_position()

      normal = PositionCodec.encode(position)

      swapped =
        position
        |> PositionTransform.swap_colors()
        |> PositionCodec.encode()

      assert PositionKey.equivalent(position, :color_swap) ==
               min(normal, swapped)
    end
  end

  describe "equivalent_hash/2" do
    test "returns the hash of the equivalent key" do
      position = Position.starting_position()

      assert PositionKey.equivalent_hash(position, :color_swap) ==
               PositionHash.hash(PositionKey.equivalent(position, :color_swap))
    end

    test "color-swapped positions have the same equivalent hash" do
      position = Position.starting_position()
      swapped = PositionTransform.swap_colors(position)

      assert PositionKey.equivalent_hash(position, :color_swap) ==
               PositionKey.equivalent_hash(swapped, :color_swap)
    end
  end
end
