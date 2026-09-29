defmodule Analysis.GameStoreDiskIntegrationTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameContentCodec
  alias Analysis.GameFingerprint
  alias Analysis.GameStore
  alias Chess.Move
  alias Chess.Square
  alias GameDB.Occurrence
  alias GameDB.Storage.Disk

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-store-disk-#{System.unique_integer([:positive])}"
      )

    server =
      :"disk-game-store-#{System.unique_integer([:positive])}"

    previous =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    opts = [
      codec: GameContentCodec,
      fingerprint_format_id: GameFingerprint.format_id(),
      fingerprint_size: GameFingerprint.fingerprint_size(),
      bucket_count: 4,
      position_bucket_count: 4
    ]

    on_exit(fn ->
      restore_config(previous)
      File.rm_rf!(directory)
    end)

    %{
      directory: directory,
      server: server,
      opts: opts
    }
  end

  test "persists GameStore data across a disk reopen", %{
    directory: directory,
    server: server,
    opts: opts
  } do
    content =
      GameContent.new(
        10,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    position_ids = [
      10,
      20,
      30
    ]

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, disk} =
             Disk.create(
               directory,
               opts
             )

    {:ok, first_store} =
      GameStore.start_link(
        server: server,
        storage: {
          Disk,
          disk
        }
      )

    Application.put_env(
      :analysis,
      GameStore,
      server: server
    )

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               position_ids
             )

    assert game_id == 1

    assert {:ok, ^content, occurrences} =
             GameStore.load(game_id)

    assert occurrences ==
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
             ]

    GenServer.stop(first_store)

    assert {:ok, reopened_disk} =
             Disk.open(
               directory,
               opts
             )

    {:ok, second_store} =
      GameStore.start_link(
        server: server,
        storage: {
          Disk,
          reopened_disk
        }
      )

    on_exit(fn ->
      if Process.alive?(second_store) do
        GenServer.stop(second_store)
      end
    end)

    assert GameStore.cardinality() == 1

    assert GameStore.find(
             fingerprint,
             content
           ) ==
             {:ok, game_id}

    assert {:ok, ^content, reopened_occurrences} =
             GameStore.load(game_id)

    assert reopened_occurrences ==
             occurrences

    assert {:ok, same_game_id} =
             GameStore.put(
               fingerprint,
               content,
               position_ids
             )

    assert same_game_id == game_id
    assert GameStore.cardinality() == 1
  end

  defp move(from, to) do
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
