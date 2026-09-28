defmodule Analysis.GameFingerprintTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Chess.Move
  alias Chess.Square

  test "produces the same fingerprint for the same canonical content" do
    content =
      content(
        42,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    assert {:ok, fingerprint_1} =
             GameFingerprint.for_content(content)

    assert {:ok, fingerprint_2} =
             GameFingerprint.for_content(content)

    assert fingerprint_1 == fingerprint_2
  end

  test "produces a 256 bit fingerprint" do
    content =
      content(
        42,
        [
          move("e2", "e4")
        ]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert byte_size(fingerprint) == 32
  end

  test "different initial positions produce different fingerprints" do
    moves = [
      move("e2", "e4")
    ]

    assert {:ok, fingerprint_1} =
             GameFingerprint.for_content(
               content(
                 42,
                 moves
               )
             )

    assert {:ok, fingerprint_2} =
             GameFingerprint.for_content(
               content(
                 43,
                 moves
               )
             )

    refute fingerprint_1 == fingerprint_2
  end

  test "different move sequences produce different fingerprints" do
    assert {:ok, fingerprint_1} =
             GameFingerprint.for_content(
               content(
                 42,
                 [
                   move("e2", "e4"),
                   move("e7", "e5")
                 ]
               )
             )

    assert {:ok, fingerprint_2} =
             GameFingerprint.for_content(
               content(
                 42,
                 [
                   move("e2", "e4"),
                   move("c7", "c5")
                 ]
               )
             )

    refute fingerprint_1 == fingerprint_2
  end

  test "promotion contributes to the fingerprint" do
    without_promotion =
      content(
        42,
        [
          Move.new(48, 56)
        ]
      )

    with_promotion =
      content(
        42,
        [
          Move.new(
            48,
            56,
            :queen
          )
        ]
      )

    assert {:ok, fingerprint_1} =
             GameFingerprint.for_content(without_promotion)

    assert {:ok, fingerprint_2} =
             GameFingerprint.for_content(with_promotion)

    refute fingerprint_1 == fingerprint_2
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
