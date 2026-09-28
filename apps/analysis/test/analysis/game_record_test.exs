defmodule Analysis.GameRecordTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameRecord
  alias Analysis.GameStart
  alias Chess.Move
  alias Chess.Square

  test "creates a record for a canonical game" do
    record =
      GameRecord.new(
        "record-1",
        42,
        %{
          white: "Adolf Anderssen",
          black: "Lionel Kieseritzky",
          event: "London",
          date: "1851",
          result: "1-0"
        }
      )

    assert GameRecord.id(record) ==
             "record-1"

    assert GameRecord.game_id(record) ==
             42

    assert GameRecord.start(record) ==
             GameStart.standard()

    assert GameRecord.metadata(record) == %{
             white: "Adolf Anderssen",
             black: "Lionel Kieseritzky",
             event: "London",
             date: "1851",
             result: "1-0"
           }
  end

  test "multiple records can reference the same canonical game" do
    historical =
      GameRecord.new(
        "historical-game",
        42,
        %{
          white: "Adolf Anderssen",
          black: "Lionel Kieseritzky",
          event: "London",
          date: "1851"
        }
      )

    modern =
      GameRecord.new(
        "modern-game",
        42,
        %{
          white: "Player C",
          black: "Player D",
          event: "Groningen",
          date: "2023"
        }
      )

    assert GameRecord.id(historical) !=
             GameRecord.id(modern)

    assert GameRecord.game_id(historical) ==
             GameRecord.game_id(modern)

    assert GameRecord.metadata(historical) !=
             GameRecord.metadata(modern)
  end

  test "move-number context belongs to the game record" do
    game_id = 42

    first =
      GameRecord.new(
        "record-1",
        game_id,
        GameStart.new(1),
        %{}
      )

    second =
      GameRecord.new(
        "record-2",
        game_id,
        GameStart.new(37),
        %{}
      )

    assert GameRecord.game_id(first) ==
             GameRecord.game_id(second)

    assert GameRecord.start(first) ==
             GameStart.new(1)

    assert GameRecord.start(second) ==
             GameStart.new(37)
  end

  test "creates an empty record with standard context" do
    record =
      GameRecord.new(
        "record-1",
        42
      )

    assert GameRecord.game_id(record) == 42
    assert GameRecord.start(record) == GameStart.standard()
    assert GameRecord.metadata(record) == %{}
  end

  test "creates a game record from an existing game" do
    game =
      Game.new(
        "played-game-1",
        7,
        GameStart.new(37),
        [
          move("e7", "e5")
        ],
        %{
          white: "White",
          black: "Black",
          event: "Example"
        }
      )

    record =
      GameRecord.from_game(
        game,
        42
      )

    assert GameRecord.id(record) ==
             "played-game-1"

    assert GameRecord.game_id(record) ==
             42

    assert GameRecord.start(record) ==
             GameStart.new(37)

    assert GameRecord.metadata(record) == %{
             white: "White",
             black: "Black",
             event: "Example"
           }
  end

  test "game record projection excludes canonical chess content" do
    game =
      Game.new(
        "played-game-1",
        7,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ],
        %{
          event: "Example"
        }
      )

    record =
      GameRecord.from_game(
        game,
        42
      )

    refute Map.has_key?(
             Map.from_struct(record),
             :initial_position_id
           )

    refute Map.has_key?(
             Map.from_struct(record),
             :moves
           )
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
