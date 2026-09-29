defmodule Analysis.GameContentCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Analysis.GameContentCodec
  alias Chess.Move
  alias Chess.Square

  test "exposes the canonical game content format" do
    assert GameContentCodec.format_id() ==
             <<"OCLGAME1">>
  end

  test "encodes canonical game content deterministically" do
    content =
      content(
        42,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    assert GameContentCodec.encode(content) ==
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

  test "round trips canonical game content" do
    content =
      content(
        42,
        [
          move("e2", "e4"),
          move("e7", "e5"),
          Move.new(
            Square.from_algebraic("a7"),
            Square.from_algebraic("a8"),
            :queen
          )
        ]
      )

    assert {:ok, encoded} =
             GameContentCodec.encode(content)

    assert GameContentCodec.decode(encoded) ==
             {:ok, content}
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

    assert GameContentCodec.encode(content) ==
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

  test "rejects an invalid initial position id" do
    assert GameContentCodec.encode(
             content(
               0,
               []
             )
           ) ==
             {:error, :invalid_initial_position_id}
  end

  test "rejects an invalid move when encoding" do
    invalid_move =
      %Move{
        from: 64,
        to: 0,
        promotion: nil
      }

    assert GameContentCodec.encode(
             content(
               42,
               [invalid_move]
             )
           ) ==
             {:error, :invalid_move}
  end

  test "rejects an unknown record format" do
    encoded =
      <<
        "OCLGAME2",
        42::unsigned-big-64,
        0::unsigned-big-32
      >>

    assert GameContentCodec.decode(encoded) ==
             {:error, :invalid_format}
  end

  test "rejects a record whose move count does not match its size" do
    encoded =
      <<
        "OCLGAME1",
        42::unsigned-big-64,
        1::unsigned-big-32
      >>

    assert GameContentCodec.decode(encoded) ==
             {:error, :invalid_record_size}
  end

  test "rejects an invalid encoded square" do
    encoded =
      <<
        "OCLGAME1",
        42::unsigned-big-64,
        1::unsigned-big-32,
        64,
        28,
        0
      >>

    assert GameContentCodec.decode(encoded) ==
             {:error, :invalid_move}
  end

  test "rejects an invalid encoded promotion" do
    encoded =
      <<
        "OCLGAME1",
        42::unsigned-big-64,
        1::unsigned-big-32,
        48,
        56,
        5
      >>

    assert GameContentCodec.decode(encoded) ==
             {:error, :invalid_promotion}
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
