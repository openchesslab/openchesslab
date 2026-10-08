defmodule Analysis.PositionSemiOpenFilesTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "encodes semi-open files separately by color" do
    assert PositionPropertyKeyCodec.encode(
             :semi_open_files,
             {:white, :e}
           ) == {:ok, <<3, 0, 4>>}

    assert PositionPropertyKeyCodec.encode(
             :semi_open_files,
             {:black, :e}
           ) == {:ok, <<3, 1, 4>>}

    assert PositionPropertyKeyCodec.encode(
             :semi_open_files,
             {:white, :a}
           ) == {:ok, <<3, 0, 0>>}

    assert PositionPropertyKeyCodec.encode(
             :semi_open_files,
             {:black, :h}
           ) == {:ok, <<3, 1, 7>>}
  end

  test "rejects invalid semi-open file values" do
    for value <- [
          {:white, :i},
          {:red, :e},
          {:white, 4},
          :e,
          nil
        ] do
      assert PositionPropertyKeyCodec.encode(
               :semi_open_files,
               value
             ) == {:error, :invalid_semi_open_file}
    end
  end

  test "semi-open file keys differ from fully open file keys" do
    assert {:ok, open_key} =
             PositionPropertyKeyCodec.encode(:open_files, :e)

    assert {:ok, white_key} =
             PositionPropertyKeyCodec.encode(
               :semi_open_files,
               {:white, :e}
             )

    assert {:ok, black_key} =
             PositionPropertyKeyCodec.encode(
               :semi_open_files,
               {:black, :e}
             )

    assert Enum.uniq([open_key, white_key, black_key]) ==
             [open_key, white_key, black_key]
  end
end
