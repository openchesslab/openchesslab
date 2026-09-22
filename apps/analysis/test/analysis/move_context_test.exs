defmodule Analysis.MoveContextTest do
  use ExUnit.Case, async: true

  alias Analysis.MoveContext

  test "calculates move context from a standard white start" do
    assert MoveContext.at(1, :white, 0) ==
             %MoveContext{
               fullmove_number: 1,
               side: :white
             }

    assert MoveContext.at(1, :white, 1) ==
             %MoveContext{
               fullmove_number: 1,
               side: :black
             }

    assert MoveContext.at(1, :white, 2) ==
             %MoveContext{
               fullmove_number: 2,
               side: :white
             }
  end

  test "calculates move context when the root starts with black" do
    assert MoveContext.at(37, :black, 0) ==
             %MoveContext{
               fullmove_number: 37,
               side: :black
             }

    assert MoveContext.at(37, :black, 1) ==
             %MoveContext{
               fullmove_number: 38,
               side: :white
             }

    assert MoveContext.at(37, :black, 2) ==
             %MoveContext{
               fullmove_number: 38,
               side: :black
             }
  end

  test "continues fullmove numbering across multiple plies" do
    assert MoveContext.at(12, :white, 5) ==
             %MoveContext{
               fullmove_number: 14,
               side: :black
             }

    assert MoveContext.at(12, :black, 5) ==
             %MoveContext{
               fullmove_number: 15,
               side: :white
             }
  end

  test "variation child indexes do not affect move context" do
    main_path = [0, 0, 0]
    variation_path = [0, 1, 0]

    assert MoveContext.at(1, :white, length(main_path)) ==
             MoveContext.at(
               1,
               :white,
               length(variation_path)
             )
  end
end
