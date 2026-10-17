defmodule Analysis.PositionTablebasesTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionStore
  alias Analysis.PositionTablebases
  alias Chess.Position
  alias OpenChessLab.Repo

  setup do
    Repo.query!("TRUNCATE TABLE position_tablebases, positions RESTART IDENTITY CASCADE", [])
    :ok
  end

  test "stores and reads back a tablebase result per position" do
    position_id = PositionStore.append(Position.starting_position())

    assert :not_found = PositionTablebases.get(position_id)

    result = %{
      "category" => "win",
      "dtz" => 3,
      "dtm" => 7,
      "moves" => [%{"uci" => "d1d8", "san" => "Qd8+", "category" => "loss", "dtz" => -2}]
    }

    assert :ok = PositionTablebases.put(position_id, result)
    assert {:ok, stored} = PositionTablebases.get(position_id)
    assert stored == result

    # Stored as a jsonb object, not a double-encoded string.
    assert Repo.query!(
             "SELECT jsonb_typeof(result) FROM position_tablebases WHERE position_id = $1",
             [position_id]
           ).rows == [["object"]]
  end

  test "a fetched result replaces the row in place" do
    position_id = PositionStore.append(Position.starting_position())
    :ok = PositionTablebases.put(position_id, %{"category" => "draw", "dtz" => 0, "moves" => []})

    :ok = PositionTablebases.put(position_id, %{"category" => "win", "dtz" => 1, "moves" => []})

    assert {:ok, %{"category" => "win", "dtz" => 1}} = PositionTablebases.get(position_id)
  end

  test "results are removed together with their position" do
    position_id = PositionStore.append(Position.starting_position())
    :ok = PositionTablebases.put(position_id, %{"category" => "draw", "moves" => []})

    Repo.query!("DELETE FROM positions WHERE id = $1", [position_id])

    assert :not_found = PositionTablebases.get(position_id)
  end
end
