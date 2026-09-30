defmodule OpenChessLab.Database.ApplicationTest do
  use ExUnit.Case, async: false

  alias OpenChessLab.Database.Application, as: DatabaseApplication
  alias OpenChessLab.Repo

  setup do
    previous =
      Application.fetch_env(
        :database,
        :start_repo
      )

    on_exit(fn ->
      restore_start_repo(previous)
    end)

    :ok
  end

  test "does not start the repository by default" do
    Application.put_env(
      :database,
      :start_repo,
      false
    )

    assert DatabaseApplication.children() ==
             []
  end

  test "starts the shared repository when enabled" do
    Application.put_env(
      :database,
      :start_repo,
      true
    )

    assert DatabaseApplication.children() ==
             [Repo]
  end

  defp restore_start_repo({:ok, value}) do
    Application.put_env(
      :database,
      :start_repo,
      value
    )
  end

  defp restore_start_repo(:error) do
    Application.delete_env(
      :database,
      :start_repo
    )
  end
end
