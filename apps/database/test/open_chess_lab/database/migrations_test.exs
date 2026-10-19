defmodule OpenChessLab.Database.MigrationsTest do
  use ExUnit.Case, async: false

  alias OpenChessLab.Database.Migrations

  test "expected versions are sorted and cover every migration file" do
    versions = Migrations.expected_versions()

    assert versions != []
    assert versions == Enum.sort(versions)
    assert 202_609_301_403_00 in versions
  end

  test "missing is empty on a current database" do
    assert Migrations.missing() == []
  end
end
