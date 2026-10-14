defmodule Analysis.LibraryBranchTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.GameContent
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  defp move(from, to), do: Move.new(Square.from_algebraic(from), Square.from_algebraic(to))

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    record_id = "branch-record-#{suffix}"
    game_entry_id = "branch-game-#{suffix}"
    plain_id = "branch-plain-#{suffix}"

    initial_position_id = PositionStore.append(Position.starting_position())
    content = GameContent.new(initial_position_id, [move("e2", "e4"), move("e7", "e5")])

    {:ok, _record} =
      GameRecords.create(record_id, content, GameStart.standard(), %{
        "white" => "W",
        "black" => "B"
      })

    {:ok, _game_analysis, 1} = Analyses.create_from_game_record(game_entry_id, record_id)
    {:ok, _plain_analysis, 1} = Analyses.create(plain_id)
    :ok = UserLibrary.save(user.id, game_entry_id)
    :ok = UserLibrary.save(user.id, plain_id)

    # Private analysis work on the game entry that a game branch must not carry.
    assert {:ok, _analysis, 2} = Analyses.set_comment(game_entry_id, [0], "Private teacher notes")

    on_exit(fn ->
      Repo.query!("DELETE FROM analyses WHERE analysis_id = ANY($1)", [
        [game_entry_id, plain_id]
      ])

      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{
      user: user,
      other: other,
      record_id: record_id,
      game_entry_id: game_entry_id,
      plain_id: plain_id
    }
  end

  test "branch_game creates a fresh analysis with the game's line and none of the private work",
       ctx do
    assert {:ok, fresh_id} = UserLibrary.branch_game(ctx.user.id, ctx.game_entry_id)
    refute fresh_id == ctx.game_entry_id

    assert {:ok, fresh, 1} = AnalysisStore.get(fresh_id)
    assert fresh.source_game_record_id == ctx.record_id

    assert {:ok, entry, 2} = AnalysisStore.get(ctx.game_entry_id)

    # The game's main line is present, the private comment is not.
    assert Node.position_id(AnalysisModel.node_at(fresh, [0])) ==
             Node.position_id(AnalysisModel.node_at(entry, [0]))

    assert Node.comment(AnalysisModel.node_at(entry, [0])) == "Private teacher notes"
    assert Node.comment(AnalysisModel.node_at(fresh, [0])) == nil

    # The library entry itself keeps its own identity and private work.
    assert {:ok, ^entry, 2} = AnalysisStore.get(ctx.game_entry_id)

    assert Enum.sort(UserLibrary.list(ctx.user.id)) ==
             Enum.sort([ctx.game_entry_id, ctx.plain_id])
  end

  test "branch_analysis copies the whole aggregate and later work diverges", ctx do
    assert {:ok, fresh_id} = UserLibrary.branch_analysis(ctx.user.id, ctx.game_entry_id)
    assert {:ok, copy, 1} = AnalysisStore.get(fresh_id)
    assert {:ok, entry, 2} = AnalysisStore.get(ctx.game_entry_id)
    assert %{copy | id: entry.id} == entry

    # Room work on the original never flows back into the branch copy.
    {:ok, changed} = AnalysisModel.set_comment(entry, [0, 0], "Room work on the original")
    assert {:ok, 3} = AnalysisStore.update(changed, 2)
    assert {:ok, ^copy, 1} = AnalysisStore.get(fresh_id)
  end

  test "entries without an underlying game cannot branch the game", ctx do
    assert {:error, :game_not_available} = UserLibrary.branch_game(ctx.user.id, ctx.plain_id)
  end

  test "unknown users and foreign entries are rejected", ctx do
    assert {:error, :invalid_identity} = UserLibrary.branch_game("invalid", ctx.game_entry_id)
    assert {:error, :invalid_identity} = UserLibrary.branch_game(ctx.user.id, nil)

    assert {:error, :analysis_not_found} =
             UserLibrary.branch_game(ctx.other.id, ctx.game_entry_id)

    assert {:error, :analysis_not_found} = UserLibrary.branch_game(ctx.user.id, "missing")
    assert {:error, :invalid_identity} = UserLibrary.branch_analysis("invalid", ctx.plain_id)
    assert {:error, :analysis_not_found} = UserLibrary.branch_analysis(ctx.other.id, ctx.plain_id)
    assert {:error, :analysis_not_found} = UserLibrary.branch_analysis(ctx.user.id, "missing")
    assert {:error, :invalid_identity} = UserLibrary.authorize_share("invalid", ctx.game_entry_id)
    assert {:error, :analysis_not_found} = UserLibrary.authorize_share(ctx.user.id, "missing")
  end

  test "page reports per-entry game availability", ctx do
    assert :ok = UserLibrary.authorize_share(ctx.user.id, ctx.game_entry_id)

    entries = UserLibrary.page(ctx.user.id).entries
    game_entry = Enum.find(entries, &(&1.id == ctx.game_entry_id))
    plain = Enum.find(entries, &(&1.id == ctx.plain_id))
    assert game_entry.game_record_id == ctx.record_id
    assert plain.game_record_id == nil
  end
end
