defmodule Analysis.GameStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameStore
  alias Chess.Move
  alias Chess.Square
  alias GameDB.Occurrence

  setup do
    previous =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    server =
      :"game-store-#{System.unique_integer([:positive])}"

    start_supervised!({
      GameStore,
      server: server
    })

    Application.put_env(
      :analysis,
      GameStore,
      server: server
    )

    on_exit(fn ->
      restore_config(previous)
    end)

    %{
      server: server
    }
  end

  test "registers under the configured server name", %{
    server: server
  } do
    assert is_pid(Process.whereis(server))
  end

  test "provides a cluster-wide server reference" do
    assert GameStore.clustered_server() ==
             {
               :via,
               Horde.Registry,
               {
                 Analysis.GameStoreRegistry,
                 :game_store
               }
             }
  end

  test "stores and retrieves canonical game content" do
    content =
      GameContent.new(10)

    assert {:ok, game_id} =
             GameStore.put(
               <<"game-1">>,
               content,
               [10]
             )

    assert game_id == 1

    assert GameStore.get(game_id) ==
             {:ok, content}
  end

  test "finds canonical game content" do
    content =
      GameContent.new(10)

    fingerprint =
      <<"game-1">>

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [10]
             )

    assert GameStore.find(
             fingerprint,
             content
           ) ==
             {:ok, game_id}
  end

  test "returns the existing id for duplicate canonical content" do
    content =
      GameContent.new(10)

    fingerprint =
      <<"same-game">>

    assert {:ok, first_id} =
             GameStore.put(
               fingerprint,
               content,
               [10]
             )

    assert {:ok, second_id} =
             GameStore.put(
               fingerprint,
               content,
               [10]
             )

    assert second_id ==
             first_id

    assert GameStore.cardinality() ==
             1
  end

  test "stores position occurrences in ply order" do
    content =
      GameContent.new(
        10,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    assert {:ok, game_id} =
             GameStore.put(
               <<"game">>,
               content,
               [10, 20, 30]
             )

    assert GameStore.occurrences(game_id) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  game_id,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  game_id,
                  1,
                  20
                ),
                Occurrence.new(
                  3,
                  game_id,
                  2,
                  30
                )
              ]}

    assert GameStore.get_occurrence(2) ==
             {:ok,
              Occurrence.new(
                2,
                game_id,
                1,
                20
              )}
  end

  test "returns not_found for an unknown game" do
    assert GameStore.get(999_999_999) ==
             :not_found
  end

  test "does not update the database when storing fails" do
    content =
      GameContent.new(10)

    assert GameStore.put(
             <<"game">>,
             content,
             []
           ) ==
             {:error, :missing_initial_position}

    assert GameStore.cardinality() ==
             0
  end

  test "returns the number of canonical games" do
    assert {:ok, _game_id} =
             GameStore.put(
               <<"game-1">>,
               GameContent.new(10),
               [10]
             )

    assert {:ok, _game_id} =
             GameStore.put(
               <<"game-2">>,
               GameContent.new(20),
               [20]
             )

    assert GameStore.cardinality() ==
             2
  end

  test "uses the configured server", %{
    server: server
  } do
    assert GameStore.server() ==
             server
  end

  test "uses the cluster-wide server by default" do
    Application.delete_env(
      :analysis,
      GameStore
    )

    assert GameStore.server() ==
             GameStore.clustered_server()
  end

  test "reports ready when the configured game store is reachable" do
    assert GameStore.ready?()
  end

  test "reports not ready when the configured game store is unavailable" do
    Application.put_env(
      :analysis,
      GameStore,
      server: :unavailable_game_store
    )

    refute GameStore.ready?()
  end

  defp move(
         from,
         to
       ) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp restore_config(:not_configured) do
    Application.delete_env(
      :analysis,
      GameStore
    )
  end

  defp restore_config(value) do
    Application.put_env(
      :analysis,
      GameStore,
      value
    )
  end
end
