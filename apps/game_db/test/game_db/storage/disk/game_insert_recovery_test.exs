defmodule GameDB.Storage.Disk.GameInsertRecoveryTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameInsertMarker
  alias GameDB.Storage.Disk.GameInsertRecovery
  alias GameDB.Storage.Disk.OccurrenceStorage

  defmodule TestCodec do
    @moduledoc false
    @behaviour GameDB.RecordCodec

    @impl true
    @spec format_id() :: binary()
    def format_id do
      <<"test-game-v1">>
    end

    @impl true
    def encode({:game, value}) when is_integer(value) and value >= 0 do
      {:ok,
       <<
         value::unsigned-big-64
       >>}
    end

    def encode(_record) do
      {:error, :invalid_game}
    end

    @impl true
    def decode(<<value::unsigned-big-64>>) do
      {:ok, {:game, value}}
    end

    def decode(_encoded) do
      {:error, :invalid_game_record}
    end
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-insert-recovery-#{System.unique_integer([:positive])}"
      )

    canonical_directory =
      Path.join(
        directory,
        "canonical"
      )

    occurrence_directory =
      Path.join(
        directory,
        "occurrences"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, canonical_store} =
             CanonicalStore.create(
               canonical_directory,
               codec: TestCodec,
               bucket_count: 4
             )

    assert {:ok, occurrence_storage} =
             OccurrenceStorage.create(
               occurrence_directory,
               position_bucket_count: 4
             )

    %{
      directory: directory,
      canonical_store: canonical_store,
      occurrence_storage: occurrence_storage
    }
  end

  test "does nothing when no game insert is pending", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    assert GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ) ==
             :ok
  end

  test "clears an insert that did not publish its canonical game", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [
                 10,
                 20
               ]
             )

    assert :ok =
             GameInsertRecovery.recover(
               directory,
               canonical_store,
               occurrence_storage
             )

    assert GameInsertMarker.read(directory) ==
             :none

    assert CanonicalStore.cardinality(canonical_store) ==
             {:ok, 0}

    assert OccurrenceStorage.occurrences(
             occurrence_storage,
             1
           ) ==
             :not_found
  end

  test "rolls forward occurrences for a published canonical game", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    position_ids =
      [
        10,
        20,
        10
      ]

    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               position_ids
             )

    assert {:ok, canonical_store, 1} =
             CanonicalStore.put(
               canonical_store,
               fingerprint(1),
               {:game, 42}
             )

    assert :ok =
             GameInsertRecovery.recover(
               directory,
               canonical_store,
               occurrence_storage
             )

    assert OccurrenceStorage.occurrences(
             occurrence_storage,
             1
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  1,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  1,
                  1,
                  20
                ),
                Occurrence.new(
                  3,
                  1,
                  2,
                  10
                )
              ]}

    assert GameInsertMarker.read(directory) ==
             :none
  end

  test "clears the marker when occurrences were already published", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    position_ids =
      [
        10,
        20
      ]

    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               position_ids
             )

    assert {:ok, canonical_store, 1} =
             CanonicalStore.put(
               canonical_store,
               fingerprint(1),
               {:game, 42}
             )

    assert :ok =
             OccurrenceStorage.append(
               occurrence_storage,
               1,
               position_ids
             )

    assert :ok =
             GameInsertRecovery.recover(
               directory,
               canonical_store,
               occurrence_storage
             )

    assert GameInsertMarker.read(directory) ==
             :none

    assert OccurrenceStorage.occurrences(
             occurrence_storage,
             1
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  1,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  1,
                  1,
                  20
                )
              ]}
  end

  test "rejects published occurrences that do not match the pending insert", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [
                 10,
                 20
               ]
             )

    assert {:ok, canonical_store, 1} =
             CanonicalStore.put(
               canonical_store,
               fingerprint(1),
               {:game, 42}
             )

    assert :ok =
             OccurrenceStorage.append(
               occurrence_storage,
               1,
               [
                 10,
                 30
               ]
             )

    assert GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ) ==
             {:error,
              {
                :game_occurrence_mismatch,
                1
              }}

    assert GameInsertMarker.read(directory) ==
             {:ok,
              %{
                game_id: 1,
                position_ids: [
                  10,
                  20
                ]
              }}
  end

  test "does not discard a marker for an unexpected unpublished game id", %{
    directory: directory,
    canonical_store: canonical_store,
    occurrence_storage: occurrence_storage
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               2,
               [10]
             )

    assert GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ) ==
             {:error,
              {
                :unexpected_pending_game_id,
                2,
                1
              }}

    assert GameInsertMarker.read(directory) ==
             {:ok,
              %{
                game_id: 2,
                position_ids: [10]
              }}
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end
end
