defmodule Analysis.GameDbIntegrationTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameReplay
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionKey
  alias Chess.Square
  alias GameDB.Storage.Memory, as: GameStorage

  test "stores canonical game content with PositionDB occurrences" do
    position_db =
      new_position_db()

    {position_db, initial_position_id} =
      PositionDB.append(
        position_db,
        Position.starting_position()
      )

    e4 =
      move(
        "e2",
        "e4"
      )

    e5 =
      move(
        "e7",
        "e5"
      )

    content =
      GameContent.new(
        initial_position_id,
        [e4, e5]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, replay} =
             GameReplay.replay(
               content,
               fn position_id ->
                 PositionDB.get(
                   position_db,
                   position_id
                 )
               end
             )

    {position_db, position_ids} =
      append_replay(
        position_db,
        initial_position_id,
        replay
      )

    game_db =
      GameDB.new(
        GameStorage,
        GameStorage.new()
      )

    {game_db, game_id} =
      GameDB.put(
        game_db,
        fingerprint,
        content,
        position_ids
      )

    assert game_id == 1

    assert GameDB.get(
             game_db,
             game_id
           ) ==
             {:ok, content}

    assert {:ok, occurrences} =
             GameDB.occurrences(
               game_db,
               game_id
             )

    assert Enum.map(
             occurrences,
             & &1.position_id
           ) ==
             position_ids

    assert Enum.map(
             occurrences,
             & &1.ply
           ) ==
             [0, 1, 2]

    assert Enum.map(
             position_ids,
             &PositionDB.get(
               position_db,
               &1
             )
           ) ==
             [
               {:ok, Position.starting_position()},
               {:ok,
                replay
                |> Enum.at(0)
                |> elem(1)},
               {:ok,
                replay
                |> Enum.at(1)
                |> elem(1)}
             ]
  end

  test "different played-game metadata shares the same canonical game" do
    position_db =
      new_position_db()

    {position_db, initial_position_id} =
      PositionDB.append(
        position_db,
        Position.starting_position()
      )

    moves = [
      move(
        "e2",
        "e4"
      ),
      move(
        "e7",
        "e5"
      )
    ]

    content =
      GameContent.new(
        initial_position_id,
        moves
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, replay} =
             GameReplay.replay(
               content,
               fn position_id ->
                 PositionDB.get(
                   position_db,
                   position_id
                 )
               end
             )

    {_position_db, position_ids} =
      append_replay(
        position_db,
        initial_position_id,
        replay
      )

    game_db =
      GameDB.new(
        GameStorage,
        GameStorage.new()
      )

    {game_db, game_id} =
      GameDB.put(
        game_db,
        fingerprint,
        content,
        position_ids
      )

    {game_db, same_game_id} =
      GameDB.put(
        game_db,
        fingerprint,
        content,
        position_ids
      )

    assert same_game_id ==
             game_id

    assert GameDB.cardinality(game_db) == 1

    historical_record =
      GameRecord.new(
        "historical-import",
        game_id,
        %{
          white: "Adolf Anderssen",
          black: "Lionel Kieseritzky",
          event: "London 1851"
        }
      )

    modern_record =
      GameRecord.new(
        "modern-import",
        game_id,
        %{
          white: "Player C",
          black: "Player D",
          event: "Groningen 2023"
        }
      )

    assert GameRecord.id(historical_record) !=
             GameRecord.id(modern_record)

    assert GameRecord.game_id(historical_record) ==
             GameRecord.game_id(modern_record)

    assert GameRecord.metadata(historical_record) !=
             GameRecord.metadata(modern_record)
  end

  defp new_position_db do
    PositionDB.new(
      key_function: &PositionKey.exact/1,
      properties: []
    )
  end

  defp append_replay(position_db, initial_position_id, replay) do
    {position_db, reversed_ids} =
      Enum.reduce(
        replay,
        {
          position_db,
          [initial_position_id]
        },
        fn {_move, position}, {position_db, position_ids} ->
          {position_db, position_id} =
            PositionDB.append(
              position_db,
              position
            )

          {
            position_db,
            [position_id | position_ids]
          }
        end
      )

    {
      position_db,
      Enum.reverse(reversed_ids)
    }
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
