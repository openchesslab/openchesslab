Code.require_file(Path.expand("../../benchmarks/pgn_long_game_fixture.exs", __DIR__))

defmodule Analysis.PgnLongGameFixtureTest do
  use ExUnit.Case, async: true

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture

  test "creates distinct, fully legal long games with the requested ply count" do
    path = temporary_path()
    on_exit(fn -> File.rm(path) end)

    assert PgnLongGameFixture.build_fixture(path, 12, 16, 0) > 0
    assert {:ok, parsed} = path |> File.read!() |> PgnBatchImporter.parse()

    assert length(parsed) == 12
    assert Enum.all?(parsed, fn game -> length(game.moves) == 16 end)
    assert length(Enum.uniq_by(parsed, & &1.moves)) == 12
  end

  test "distributes an exact fraction of canonical duplicates" do
    path = temporary_path()
    on_exit(fn -> File.rm(path) end)

    assert PgnLongGameFixture.build_fixture(path, 20, 12, 50) > 0
    assert {:ok, parsed} = path |> File.read!() |> PgnBatchImporter.parse()

    assert length(parsed) == 20
    assert Enum.all?(parsed, fn game -> length(game.moves) == 12 end)
    assert length(Enum.uniq_by(parsed, & &1.moves)) == 10
    assert parsed |> Enum.map(& &1.headers["Event"]) |> Enum.uniq() |> length() == 20
  end

  test "produces byte-for-byte identical fixtures for the same inputs" do
    first = temporary_path()
    second = temporary_path()

    on_exit(fn ->
      File.rm(first)
      File.rm(second)
    end)

    assert PgnLongGameFixture.build_fixture(first, 10, 14, 30) > 0
    assert PgnLongGameFixture.build_fixture(second, 10, 14, 30) > 0
    assert File.read!(first) == File.read!(second)
  end

  test "rejects invalid fixture settings" do
    assert_raise ArgumentError, fn ->
      PgnLongGameFixture.build_fixture(temporary_path(), 10, 1, 0)
    end

    assert_raise ArgumentError, fn ->
      PgnLongGameFixture.build_fixture(temporary_path(), 10, 40, 100)
    end
  end

  defp temporary_path do
    Path.join(
      System.tmp_dir!(),
      "openchesslab-long-game-test-#{System.unique_integer([:positive])}.pgn"
    )
  end
end
