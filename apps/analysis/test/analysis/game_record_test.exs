defmodule Analysis.GameRecordTest do
  use ExUnit.Case, async: true

  alias Analysis.GameRecord
  alias Analysis.GameStart

  test "creates a record for a canonical game" do
    record =
      GameRecord.new(
        "record-1",
        42,
        %{
          "white" => "Adolf Anderssen",
          "black" => "Lionel Kieseritzky",
          "event" => "London",
          "date" => "1851",
          "result" => "1-0"
        }
      )

    assert GameRecord.id(record) ==
             "record-1"

    assert GameRecord.game_id(record) ==
             42

    assert GameRecord.start(record) ==
             GameStart.standard()

    assert GameRecord.metadata(record) == %{
             "white" => "Adolf Anderssen",
             "black" => "Lionel Kieseritzky",
             "event" => "London",
             "date" => "1851",
             "result" => "1-0"
           }
  end

  test "multiple records can reference the same canonical game" do
    historical =
      GameRecord.new(
        "historical-game",
        42,
        %{
          "white" => "Adolf Anderssen",
          "black" => "Lionel Kieseritzky",
          "event" => "London",
          "date" => "1851"
        }
      )

    modern =
      GameRecord.new(
        "modern-game",
        42,
        %{
          "white" => "Player C",
          "black" => "Player D",
          "event" => "Groningen",
          "date" => "2023"
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

  test "game record excludes canonical chess content" do
    record =
      GameRecord.new(
        "played-game-1",
        42,
        %{
          "event" => "Example"
        }
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

  test "requires a non-empty textual record id" do
    assert_raise FunctionClauseError, fn ->
      GameRecord.new(
        "",
        42
      )
    end

    assert_raise FunctionClauseError, fn ->
      apply(
        GameRecord,
        :new,
        [
          123,
          42
        ]
      )
    end

    assert_raise FunctionClauseError, fn ->
      apply(
        GameRecord,
        :new,
        [
          nil,
          42
        ]
      )
    end
  end

  test "supports nested JSON-compatible metadata" do
    metadata = %{
      "event" => "Example",
      "rated" => true,
      "round" => 3,
      "score" => 0.5,
      "source" => nil,
      "players" => [
        %{
          "name" => "White",
          "rating" => 2500
        },
        %{
          "name" => "Black",
          "rating" => 2450
        }
      ]
    }

    record =
      GameRecord.new(
        "record-1",
        42,
        metadata
      )

    assert GameRecord.metadata(record) ==
             metadata

    assert GameRecord.valid_metadata?(metadata)
  end

  test "rejects metadata with non-string keys" do
    refute GameRecord.valid_metadata?(%{
             event: "Example"
           })

    assert_raise ArgumentError, fn ->
      apply(
        GameRecord,
        :new,
        [
          "record-1",
          42,
          %{
            event: "Example"
          }
        ]
      )
    end
  end

  test "rejects non-JSON metadata values" do
    metadata = %{
      "event" => {:not, :json}
    }

    refute GameRecord.valid_metadata?(metadata)

    assert_raise ArgumentError, fn ->
      apply(
        GameRecord,
        :new,
        [
          "record-1",
          42,
          metadata
        ]
      )
    end
  end
end
