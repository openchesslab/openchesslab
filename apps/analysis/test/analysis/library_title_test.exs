defmodule Analysis.LibraryTitleTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    id = "title-" <> Ecto.UUID.generate()
    {:ok, 1} = AnalysisStore.insert(AnalysisModel.new(id, 42))
    :ok = UserLibrary.save(user.id, id)
    :ok = UserLibrary.save(other.id, id)

    on_exit(fn ->
      Users.delete(user.id)
      Users.delete(other.id)
      AnalysisStore.delete(id, 1)
    end)

    %{user: user, other: other, id: id}
  end

  test "personal titles persist and do not change another user or the analysis", ctx do
    assert {:ok, nil} = UserLibrary.title(ctx.user.id, ctx.id)
    assert :ok = UserLibrary.rename(ctx.user.id, ctx.id, "  Sicilian\n  plans  ")
    assert {:ok, "Sicilian plans"} = UserLibrary.title(ctx.user.id, ctx.id)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.id)
    assert [%{id: id, title: "Sicilian plans"}] = UserLibrary.page(ctx.user.id).entries
    assert id == ctx.id
    assert {:ok, analysis, 1} = AnalysisStore.get(ctx.id)
    assert analysis.metadata == %{}
    assert :ok = UserLibrary.save(ctx.user.id, ctx.id)
    assert {:ok, "Sicilian plans"} = UserLibrary.title(ctx.user.id, ctx.id)
    assert :ok = UserLibrary.rename(ctx.user.id, ctx.id, " \n ")
    assert {:ok, nil} = UserLibrary.title(ctx.user.id, ctx.id)
  end

  test "missing, removed and foreign references cannot be renamed or read", ctx do
    :ok = UserLibrary.remove(ctx.user.id, ctx.id)
    assert :not_found = UserLibrary.rename(ctx.user.id, ctx.id, "Foreign")
    assert :not_found = UserLibrary.title(ctx.user.id, ctx.id)
    assert :not_found = UserLibrary.rename(ctx.other.id, "missing", "Foreign")
    assert :not_found = UserLibrary.title("invalid", ctx.id)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.id)
  end

  test "title limits match PostgreSQL Unicode character counting", ctx do
    boundary = String.duplicate("♞", 120)
    assert :ok = UserLibrary.rename(ctx.user.id, ctx.id, boundary)
    assert {:ok, ^boundary} = UserLibrary.title(ctx.user.id, ctx.id)

    for value <- [boundary <> "x", String.duplicate("e\u0301", 61), <<255>>, nil, %{}] do
      assert {:error, :invalid_title} = UserLibrary.rename(ctx.user.id, ctx.id, value)
    end

    assert {:ok, ^boundary} = UserLibrary.title(ctx.user.id, ctx.id)

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE user_analyses SET title = $1 WHERE user_id = $2", [
        String.duplicate("x", 121),
        Ecto.UUID.dump!(ctx.user.id)
      ])
    end
  end
end
