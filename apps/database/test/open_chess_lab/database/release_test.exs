defmodule OpenChessLab.Database.ReleaseTest do
  use ExUnit.Case, async: false

  alias OpenChessLab.Database.Release

  test "runs all database migrations idempotently" do
    assert :ok =
             Release.migrate()

    assert :ok =
             Release.migrate()
  end
end
