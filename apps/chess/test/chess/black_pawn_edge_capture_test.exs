defmodule Chess.BlackPawnEdgeCaptureTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  test "black pawn captures from the a-file toward the b-file" do
    position =
      [side_to_move: :black]
      |> Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("a5"), {:black, :pawn})
      |> Position.put_piece(square("b4"), {:white, :pawn})

    move =
      Move.new(
        square("a5"),
        square("b4")
      )

    assert move in Position.legal_moves(position)

    assert {:ok, next_position} =
             Position.apply_move(
               position,
               move
             )

    assert Position.piece_at(
             next_position,
             square("a5")
           ) ==
             nil

    assert Position.piece_at(
             next_position,
             square("b4")
           ) ==
             {:black, :pawn}
  end

  test "black pawn captures from the h-file toward the g-file" do
    position =
      [side_to_move: :black]
      |> Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("h5"), {:black, :pawn})
      |> Position.put_piece(square("g4"), {:white, :pawn})

    move =
      Move.new(
        square("h5"),
        square("g4")
      )

    assert move in Position.legal_moves(position)

    assert {:ok, next_position} =
             Position.apply_move(
               position,
               move
             )

    assert Position.piece_at(
             next_position,
             square("h5")
           ) ==
             nil

    assert Position.piece_at(
             next_position,
             square("g4")
           ) ==
             {:black, :pawn}
  end

  test "black pawn captures en passant from the a-file toward the b-file" do
    position =
      [
        side_to_move: :black,
        en_passant: square("b3")
      ]
      |> Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("a4"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        square("b4"),
        {:white, :pawn}
      )

    move =
      Move.new(
        square("a4"),
        square("b3")
      )

    assert move in Position.legal_moves(position)

    assert {:ok, next_position} =
             Position.apply_move(
               position,
               move
             )

    assert Position.piece_at(next_position, square("a4")) == nil
    assert Position.piece_at(next_position, square("b4")) == nil
    assert Position.piece_at(next_position, square("b3")) == {:black, :pawn}
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
