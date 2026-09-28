defmodule Analysis.GameFingerprintCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Analysis.GameFingerprintCodec
  alias Chess.Move
  alias Chess.Square

  test "encodes canonical game content deterministically" do
    content =
      content(
        42,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    assert GameFingerprintCodec.encode(content) ==
             {:ok,
              <<
                "OCLGAME1",
                42::unsigned-big-64,
                2::unsigned-big-32,
                12,
                28,
                0,
                52,
                36,
                0
              >>}
  end

  test "uses stable promotion codes" do
    content =
      content(
        42,
        [
          Move.new(48, 56),
          Move.new(48, 56, :queen),
          Move.new(48, 56, :rook),
          Move.new(48, 56, :bishop),
          Move.new(48, 56, :knight)
        ]
      )

    assert GameFingerprintCodec.encode(content) ==
             {:ok,
              <<
                "OCLGAME1",
                42::unsigned-big-64,
                5::unsigned-big-32,
                48,
                56,
                0,
                48,
                56,
                1,
                48,
                56,
                2,
                48,
                56,
                3,
                48,
                56,
                4
              >>}
  end

  test "different initial positions have different encodings" do
    moves = [
      move("e2", "e4")
    ]

    {:ok, first} =
      GameFingerprintCodec.encode(
        content(
          42,
          moves
        )
      )

    {:ok, second} =
      GameFingerprintCodec.encode(
        content(
          43,
          moves
        )
      )

    refute first == second
  end

  test "different move sequences have different encodings" do
    {:ok, first} =
      GameFingerprintCodec.encode(
        content(
          42,
          [
            move("e2", "e4"),
            move("e7", "e5")
          ]
        )
      )

    {:ok, second} =
      GameFingerprintCodec.encode(
        content(
          42,
          [
            move("e2", "e4"),
            move("c7", "c5")
          ]
        )
      )

    refute first == second
  end

  test "rejects an invalid initial position id" do
    assert GameFingerprintCodec.encode(
             content(
               0,
               []
             )
           ) ==
             {:error, :invalid_initial_position_id}
  end

  test "rejects an invalid move" do
    invalid_move =
      %Move{
        from: 64,
        to: 0,
        promotion: nil
      }

    assert GameFingerprintCodec.encode(
             content(
               42,
               [invalid_move]
             )
           ) ==
             {:error, :invalid_move}
  end

  defp content(initial_position_id, moves) do
    %GameContent{
      initial_position_id: initial_position_id,
      moves: moves
    }
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
