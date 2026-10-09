defmodule Analysis.PgnLongGameFixtureTest do
  use ExUnit.Case, async: true

  alias Analysis.PgnLongGameFixture

  Code.require_file(Path.expand("../../benchmarks/pgn_long_game_fixture.exs", __DIR__))

  test "writes deterministic LF-only PGN files" do
    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-long-fixture-#{System.unique_integer([:positive, :monotonic])}.pgn"
      )

    on_exit(fn -> File.rm(path) end)

    bytes = PgnLongGameFixture.build_fixture(path, 2, 4, 0)
    content = File.read!(path)

    assert bytes == byte_size(content)
    refute String.contains?(content, "\r")
    assert length(:binary.matches(content, "\n")) == 14
    assert content =~ ~s([Event "PGN long-game profile 1"])
    assert content =~ ~s([Event "PGN long-game profile 2"])

    assert PgnLongGameFixture.build_fixture(path, 2, 4, 0) == bytes
    assert File.read!(path) == content
  end
end
