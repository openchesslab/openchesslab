defmodule Chess.PositionDraftTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionDraft

  defp square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  describe "new/1" do
    test "starts with the supplied position" do
      position = Position.starting_position()

      draft = PositionDraft.new(position)

      assert PositionDraft.position(draft) == position
    end
  end

  describe "put_piece/3" do
    test "puts a piece on the draft position" do
      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.put_piece(square("d4"), {:white, :knight})

      assert Position.piece_at(PositionDraft.position(draft), square("d4")) ==
               {:white, :knight}
    end
  end

  describe "remove_piece/2" do
    test "removes a piece from the draft position" do
      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("d1"))

      assert Position.piece_at(PositionDraft.position(draft), square("d1")) == nil
    end
  end

  describe "set_side_to_move/2" do
    test "changes the side to move" do
      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.set_side_to_move(:black)

      assert PositionDraft.position(draft).side_to_move == :black
    end
  end

  describe "apply/1" do
    test "returns a valid edited position" do
      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("g1"))
        |> PositionDraft.put_piece(square("f3"), {:white, :knight})

      assert {:ok, position} = PositionDraft.apply(draft)

      assert Position.piece_at(position, square("g1")) == nil
      assert Position.piece_at(position, square("f3")) == {:white, :knight}
    end

    test "allows an invalid intermediate position to become valid before apply" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("e1"))
        |> PositionDraft.put_piece(square("e2"), {:white, :king})

      assert {:ok, position} = PositionDraft.apply(draft)

      assert Position.piece_at(position, square("e1")) == nil
      assert Position.piece_at(position, square("e2")) == {:white, :king}
    end

    test "returns validation errors for an invalid final position" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("e1"))

      assert PositionDraft.apply(draft) ==
               {:error, [:invalid_white_king_count]}
    end

    test "preserves en passant when an unrelated piece is edited" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("g1"), {:white, :knight})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("g1"))
        |> PositionDraft.put_piece(square("f3"), {:white, :knight})

      assert {:ok, edited} = PositionDraft.apply(draft)
      assert edited.en_passant == square("d6")
    end

    test "preserves castling rights when the rook returns before apply" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("h1"))
        |> PositionDraft.put_piece(square("h3"), {:white, :rook})
        |> PositionDraft.remove_piece(square("h3"))
        |> PositionDraft.put_piece(square("h1"), {:white, :rook})

      assert {:ok, edited} = PositionDraft.apply(draft)
      assert MapSet.member?(edited.castling_rights, :white_kingside)
    end

    test "rejects castling rights that are inconsistent with the final board" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(square("h1"))
        |> PositionDraft.put_piece(square("h3"), {:white, :rook})

      assert PositionDraft.apply(draft) ==
               {:error, [:invalid_castling_rights]}
    end
  end

  describe "set_castling_right/3" do
    test "enables a castling right" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.set_castling_right(:white_kingside, true)

      assert MapSet.member?(
               PositionDraft.position(draft).castling_rights,
               :white_kingside
             )

      assert {:ok, _position} = PositionDraft.apply(draft)
    end

    test "disables a castling right" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.set_castling_right(:white_kingside, false)

      refute MapSet.member?(
               PositionDraft.position(draft).castling_rights,
               :white_kingside
             )

      assert {:ok, _position} = PositionDraft.apply(draft)
    end
  end

  describe "set_en_passant/2" do
    test "sets a valid en passant target" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.set_en_passant(square("d6"))

      assert PositionDraft.position(draft).en_passant == square("d6")
      assert {:ok, _position} = PositionDraft.apply(draft)
    end

    test "clears the en passant target" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.set_en_passant(nil)

      assert PositionDraft.position(draft).en_passant == nil
      assert {:ok, _position} = PositionDraft.apply(draft)
    end

    test "allows an invalid en passant target while editing" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      draft =
        position
        |> PositionDraft.new()
        |> PositionDraft.set_en_passant(square("d6"))

      assert PositionDraft.position(draft).en_passant == square("d6")

      assert PositionDraft.apply(draft) ==
               {:error, [:invalid_en_passant]}
    end
  end
end
