defmodule OpenChessLab.RepoTest do
  use ExUnit.Case, async: true

  alias OpenChessLab.Repo

  test "uses the PostgreSQL Ecto adapter" do
    assert Repo.__adapter__() ==
             Ecto.Adapters.Postgres
  end

  test "reports ready when PostgreSQL is reachable" do
    assert Repo.ready?()
  end
end
