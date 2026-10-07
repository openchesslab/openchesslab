defmodule Analysis.PositionPawnStructureCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPawnStructureCodec
  alias Chess.PawnStructure

  test "preserves ordinary 64-bit pawn masks" do
    structure =
      %PawnStructure{
        white: 0x000000000000FF00,
        black: 0x00FF000000000000
      }

    assert PositionPawnStructureCodec.encode(structure) ==
             {:ok,
              {
                0x000000000000FF00,
                0x00FF000000000000
              }}
  end

  test "encodes the high bit using signed bigint representation" do
    structure =
      %PawnStructure{
        white: 0x8000000000000000,
        black: 0
      }

    assert PositionPawnStructureCodec.encode(structure) ==
             {:ok,
              {
                -9_223_372_036_854_775_808,
                0
              }}
  end

  test "rejects bitboards outside 64 bits" do
    structure =
      %PawnStructure{
        white: 18_446_744_073_709_551_616,
        black: 0
      }

    assert PositionPawnStructureCodec.encode(structure) ==
             {:error, :invalid_pawn_structure}
  end
end
