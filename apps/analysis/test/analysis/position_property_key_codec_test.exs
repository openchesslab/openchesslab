defmodule Analysis.PositionPropertyKeyCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "has a stable format id" do
    assert PositionPropertyKeyCodec.format_id() ==
             <<"chess-position-property-v1">>
  end

  test "encodes open files deterministically" do
    assert PositionPropertyKeyCodec.encode(
             :open_files,
             :a
           ) ==
             {:ok,
              <<
                1::unsigned-8,
                0::unsigned-8
              >>}

    assert PositionPropertyKeyCodec.encode(
             :open_files,
             :e
           ) ==
             {:ok,
              <<
                1::unsigned-8,
                4::unsigned-8
              >>}

    assert PositionPropertyKeyCodec.encode(
             :open_files,
             :h
           ) ==
             {:ok,
              <<
                1::unsigned-8,
                7::unsigned-8
              >>}
  end

  test "rejects an invalid open file" do
    assert PositionPropertyKeyCodec.encode(
             :open_files,
             :i
           ) ==
             {:error, :invalid_open_file}
  end

  test "encodes material in a stable piece order" do
    material = %{
      white: %{
        pawn: 8,
        knight: 2,
        bishop: 2,
        rook: 2,
        queen: 1,
        king: 1
      },
      black: %{
        pawn: 7,
        knight: 1,
        bishop: 2,
        rook: 2,
        queen: 1,
        king: 1
      }
    }

    assert PositionPropertyKeyCodec.encode(
             :material,
             material
           ) ==
             {:ok,
              <<
                2,
                8,
                2,
                2,
                2,
                1,
                1,
                7,
                1,
                2,
                2,
                1,
                1
              >>}
  end

  test "material map ordering does not affect encoding" do
    left = %{
      white: %{
        pawn: 8,
        knight: 2,
        bishop: 2,
        rook: 2,
        queen: 1,
        king: 1
      },
      black: %{
        pawn: 8,
        knight: 2,
        bishop: 2,
        rook: 2,
        queen: 1,
        king: 1
      }
    }

    right = %{
      black: %{
        king: 1,
        queen: 1,
        rook: 2,
        bishop: 2,
        knight: 2,
        pawn: 8
      },
      white: %{
        king: 1,
        queen: 1,
        rook: 2,
        bishop: 2,
        knight: 2,
        pawn: 8
      }
    }

    assert PositionPropertyKeyCodec.encode(
             :material,
             left
           ) ==
             PositionPropertyKeyCodec.encode(
               :material,
               right
             )
  end

  test "rejects incomplete material" do
    assert PositionPropertyKeyCodec.encode(
             :material,
             %{
               white: %{pawn: 8},
               black: %{pawn: 8}
             }
           ) ==
             {:error, :invalid_material}
  end

  test "rejects unsupported properties" do
    assert PositionPropertyKeyCodec.encode(
             :unknown,
             :value
           ) ==
             {:error, :unsupported_property}
  end
end
