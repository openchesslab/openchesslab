defmodule OpenChessLab.Database.ApplicationTest do
  use ExUnit.Case, async: true

  alias OpenChessLab.Database.Application, as: DatabaseApplication
  alias OpenChessLab.Repo

  test "starts the shared PostgreSQL repository" do
    assert DatabaseApplication.children() ==
             [Repo]
  end
end
