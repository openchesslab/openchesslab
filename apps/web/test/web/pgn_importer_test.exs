defmodule Web.PgnImporterTest do
  use ExUnit.Case, async: true

  alias Web.DemoData
  alias Web.PgnImporter

  test "parses the sample main line and validates every SAN move" do
    assert {:ok, parsed} = PgnImporter.parse(DemoData.game("demo-ruy-lopez").pgn)
    assert length(parsed.moves) == 10
    assert parsed.headers["White"] == "Alice Example"
    assert parsed.final_position.side_to_move == :white
  end

  test "reports invalid SAN rather than inventing a move" do
    assert {:error, {:invalid_pgn, message}} = PgnImporter.parse("1. e4 e5 2. ThisIsNotSAN")
    assert message =~ "Could not parse move"
  end
end
